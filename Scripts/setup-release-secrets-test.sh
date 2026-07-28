#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCRIPT="$ROOT/Scripts/setup-release-secrets.sh"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"

# Records every gh write as "<kind> <name> <value>" so tests can assert both the
# call surface and the exact bytes that would reach GitHub.
cat > "$BIN_DIR/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
kind="$1"
action="$2"
name="$3"
if [[ "$action" != "set" ]]; then
  echo "unexpected gh action: $action" >&2
  exit 1
fi
value="$(cat)"
printf '%s %s %s\n' "$kind" "$name" "$value" >> "$GH_CALL_LOG"
MOCK
chmod +x "$BIN_DIR/gh"

VALID_PUBLIC_KEY="cFzhEWKU7GTdZpF26CrZky5f678f6nYw4FqnQH68Nsg="

write_env_file() {
  local path="$1"
  cat > "$path" <<EOF
# release credentials
DEVELOPER_ID_APPLICATION=Developer ID Application: Example (ABCDE12345)
SPARKLE_PUBLIC_ED_KEY=$VALID_PUBLIC_KEY
CLOUDFLARE_ACCOUNT_ID=cf-account
TAP_GITHUB_APP_ID=12345

APPLE_CERTIFICATE_P12_BASE64=cert-base64
APPLE_CERTIFICATE_PASSWORD=cert-password
APPLE_NOTARY_KEY_P8_BASE64=notary-base64
APPLE_NOTARY_KEY_ID=notary-key-id
APPLE_NOTARY_ISSUER_ID=notary-issuer-id
R2_ACCESS_KEY_ID=r2-access
R2_SECRET_ACCESS_KEY=r2-secret
SPARKLE_PRIVATE_ED_KEY=sparkle-private
TAP_GITHUB_APP_PRIVATE_KEY=tap-private
EOF
}

# Runs the script with only the mock gh on PATH and a scrubbed credential
# environment, so a real developer shell can never leak values into the test.
run_script() {
  local env_file="$1"
  local out_file="$2"
  shift 2

  : > "$TMP_DIR/gh-calls.log"
  set +e
  env -i \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    HOME="$TMP_DIR/home" \
    GH_CALL_LOG="$TMP_DIR/gh-calls.log" \
    GITHUB_REPOSITORY="sonim1/UpdateBar" \
    UPDATEBAR_RELEASE_ENV_FILE="$env_file" \
    "$@" \
    bash "$SCRIPT" > "$out_file" 2>&1
  local status=$?
  set -e
  printf '%s' "$status"
}

assert_no_gh_calls() {
  local context="$1"
  if [[ -s "$TMP_DIR/gh-calls.log" ]]; then
    echo "$context must not reach GitHub before every value validates" >&2
    cat "$TMP_DIR/gh-calls.log" >&2
    exit 1
  fi
}

# --- happy path -------------------------------------------------------------

ENV_FILE="$TMP_DIR/.env.release.local"
write_env_file "$ENV_FILE"

OUTPUT="$TMP_DIR/happy.out"
status="$(run_script "$ENV_FILE" "$OUTPUT")"
if [[ "$status" -ne 0 ]]; then
  echo "complete credentials should upload cleanly" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

for expected in \
  "variable DEVELOPER_ID_APPLICATION Developer ID Application: Example (ABCDE12345)" \
  "variable SPARKLE_PUBLIC_ED_KEY $VALID_PUBLIC_KEY" \
  "variable CLOUDFLARE_ACCOUNT_ID cf-account" \
  "variable TAP_GITHUB_APP_ID 12345" \
  "secret APPLE_CERTIFICATE_P12_BASE64 cert-base64" \
  "secret R2_SECRET_ACCESS_KEY r2-secret" \
  "secret SPARKLE_PRIVATE_ED_KEY sparkle-private" \
  "secret TAP_GITHUB_APP_PRIVATE_KEY tap-private"; do
  if ! grep -Fxq "$expected" "$TMP_DIR/gh-calls.log"; then
    echo "missing expected gh write: $expected" >&2
    cat "$TMP_DIR/gh-calls.log" >&2
    exit 1
  fi
done

if [[ "$(grep -c . "$TMP_DIR/gh-calls.log")" -ne 13 ]]; then
  echo "expected exactly 13 credential writes" >&2
  cat "$TMP_DIR/gh-calls.log" >&2
  exit 1
fi

if grep -q "sparkle-private\|cert-password\|r2-secret" "$OUTPUT"; then
  echo "script must never print credential values" >&2
  exit 1
fi

# --- exported values win over the file --------------------------------------

OUTPUT="$TMP_DIR/override.out"
status="$(run_script "$ENV_FILE" "$OUTPUT" CLOUDFLARE_ACCOUNT_ID=exported-account)"
if [[ "$status" -ne 0 ]]; then
  echo "exported override should still upload cleanly" >&2
  cat "$OUTPUT" >&2
  exit 1
fi
if ! grep -Fxq "variable CLOUDFLARE_ACCOUNT_ID exported-account" "$TMP_DIR/gh-calls.log"; then
  echo "exported value must win over $ENV_FILE" >&2
  cat "$TMP_DIR/gh-calls.log" >&2
  exit 1
fi

# --- a missing value must abort before any upload ---------------------------

PARTIAL_ENV="$TMP_DIR/.env.partial"
grep -v '^R2_SECRET_ACCESS_KEY=' "$ENV_FILE" > "$PARTIAL_ENV"

OUTPUT="$TMP_DIR/missing.out"
status="$(run_script "$PARTIAL_ENV" "$OUTPUT")"
if [[ "$status" -eq 0 ]]; then
  echo "a missing credential must fail the run" >&2
  cat "$OUTPUT" >&2
  exit 1
fi
if ! grep -Fq "missing values: R2_SECRET_ACCESS_KEY" "$OUTPUT"; then
  echo "missing credential must be named in the failure" >&2
  cat "$OUTPUT" >&2
  exit 1
fi
assert_no_gh_calls "a run with a missing credential"

# --- an empty value must never overwrite stored credentials -----------------

EMPTY_ENV="$TMP_DIR/.env.empty-value"
sed 's/^APPLE_NOTARY_KEY_ID=.*/APPLE_NOTARY_KEY_ID=/' "$ENV_FILE" > "$EMPTY_ENV"

OUTPUT="$TMP_DIR/empty.out"
status="$(run_script "$EMPTY_ENV" "$OUTPUT")"
if [[ "$status" -eq 0 ]]; then
  echo "an empty credential must fail instead of blanking the stored value" >&2
  cat "$OUTPUT" >&2
  exit 1
fi
assert_no_gh_calls "a run with an empty credential"

# --- malformed Sparkle public keys are rejected before signing costs --------

for bad_key in "" "not-base64" "$VALID_PUBLIC_KEY=" "cFzhEWKU7GTdZpF26CrZky5f678f6nYw4FqnQH68Ns"; do
  BAD_ENV="$TMP_DIR/.env.bad-key"
  sed "s|^SPARKLE_PUBLIC_ED_KEY=.*|SPARKLE_PUBLIC_ED_KEY=$bad_key|" "$ENV_FILE" > "$BAD_ENV"

  OUTPUT="$TMP_DIR/bad-key.out"
  status="$(run_script "$BAD_ENV" "$OUTPUT")"
  if [[ "$status" -eq 0 ]]; then
    echo "malformed SPARKLE_PUBLIC_ED_KEY '$bad_key' was accepted" >&2
    cat "$OUTPUT" >&2
    exit 1
  fi
  assert_no_gh_calls "a run with a malformed Sparkle public key"
done

# --- surrounding whitespace on a variable is trimmed, not uploaded ----------

PADDED_ENV="$TMP_DIR/.env.padded"
sed "s|^SPARKLE_PUBLIC_ED_KEY=.*|SPARKLE_PUBLIC_ED_KEY=  $VALID_PUBLIC_KEY  |" "$ENV_FILE" > "$PADDED_ENV"

OUTPUT="$TMP_DIR/padded.out"
status="$(run_script "$PADDED_ENV" "$OUTPUT")"
if [[ "$status" -ne 0 ]]; then
  echo "a padded public key should be trimmed and accepted" >&2
  cat "$OUTPUT" >&2
  exit 1
fi
if ! grep -Fxq "variable SPARKLE_PUBLIC_ED_KEY $VALID_PUBLIC_KEY" "$TMP_DIR/gh-calls.log"; then
  echo "padded public key must be uploaded trimmed" >&2
  cat "$TMP_DIR/gh-calls.log" >&2
  exit 1
fi

# --- help stays credential-free ---------------------------------------------

OUTPUT="$TMP_DIR/help.out"
: > "$TMP_DIR/gh-calls.log"
set +e
env -i PATH="$BIN_DIR:/usr/bin:/bin" HOME="$TMP_DIR/home" \
  GH_CALL_LOG="$TMP_DIR/gh-calls.log" GITHUB_REPOSITORY="sonim1/UpdateBar" \
  bash "$SCRIPT" --help > "$OUTPUT" 2>&1
help_status=$?
set -e
if [[ "$help_status" -ne 0 ]]; then
  echo "--help must exit 0" >&2
  cat "$OUTPUT" >&2
  exit 1
fi
assert_no_gh_calls "--help"

# --- the example file documents exactly the required names ------------------

EXAMPLE_FILE="$ROOT/.env.release.local.example"
if [[ ! -f "$EXAMPLE_FILE" ]]; then
  echo ".env.release.local.example must exist for operators" >&2
  exit 1
fi

required_names="$(grep -oE '^\s*"[A-Z0-9_]+"' "$SCRIPT" | tr -d ' "' | sort -u)"
example_names="$(grep -oE '^[A-Z0-9_]+=' "$EXAMPLE_FILE" | tr -d '=' | sort -u)"
if [[ "$required_names" != "$example_names" ]]; then
  echo ".env.release.local.example must list exactly the required credential names" >&2
  diff <(printf '%s\n' "$required_names") <(printf '%s\n' "$example_names") >&2 || true
  exit 1
fi

if ! grep -Fxq ".env.release.local" "$ROOT/.gitignore"; then
  echo ".env.release.local must stay untracked" >&2
  exit 1
fi

echo "setup-release-secrets checks passed"
