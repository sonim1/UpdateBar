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

# Records every gh write's arguments separately from its stdin so tests can
# assert exact scopes/commands without ever printing credential values.
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
shift 3
call_number="$(wc -l < "$GH_ARG_LOG")"
call_number=$((call_number + 1))
printf '%s %s %s %s\n' "$kind" "$action" "$name" "$*" >> "$GH_ARG_LOG"
cat > "$GH_VALUE_DIR/$call_number.stdin"
value="$(< "$GH_VALUE_DIR/$call_number.stdin")"
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

APPLE_CERTIFICATE_P12_BASE64=cert-base64
APPLE_CERTIFICATE_PASSWORD=cert-password
APPLE_NOTARY_KEY_P8_BASE64=notary-base64
APPLE_NOTARY_KEY_ID=notary-key-id
APPLE_NOTARY_ISSUER_ID=notary-issuer-id
R2_ACCESS_KEY_ID=r2-access
R2_SECRET_ACCESS_KEY=r2-secret
SPARKLE_PRIVATE_ED_KEY=sparkle-private
EOF
}

# Runs the script with only the mock gh on PATH and a scrubbed credential
# environment, so a real developer shell can never leak values into the test.
run_script() {
  local env_file="$1"
  local out_file="$2"
  shift 2

  : > "$TMP_DIR/gh-calls.log"
  : > "$TMP_DIR/gh-args.log"
  rm -rf "$TMP_DIR/gh-values"
  mkdir -p "$TMP_DIR/gh-values"
  set +e
  env -i \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    HOME="$TMP_DIR/home" \
    GH_CALL_LOG="$TMP_DIR/gh-calls.log" \
    GH_ARG_LOG="$TMP_DIR/gh-args.log" \
    GH_VALUE_DIR="$TMP_DIR/gh-values" \
    GITHUB_REPOSITORY="sonim1/UpdateBar" \
    UPDATEBAR_RELEASE_ENV_FILE="$env_file" \
    "$@" \
    /bin/bash "$SCRIPT" > "$out_file" 2>&1
  local status=$?
  set -e
  printf '%s' "$status"
}

assert_no_gh_calls() {
  local context="$1"
  if [[ -s "$TMP_DIR/gh-calls.log" ]]; then
    echo "$context must not reach GitHub before every value validates" >&2
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
  exit 1
fi

for expected in \
  "variable DEVELOPER_ID_APPLICATION Developer ID Application: Example (ABCDE12345)" \
  "variable SPARKLE_PUBLIC_ED_KEY $VALID_PUBLIC_KEY" \
  "variable CLOUDFLARE_ACCOUNT_ID cf-account" \
  "secret APPLE_CERTIFICATE_P12_BASE64 cert-base64" \
  "secret R2_SECRET_ACCESS_KEY r2-secret" \
  "secret SPARKLE_PRIVATE_ED_KEY sparkle-private"; do
  if ! grep -Fxq "$expected" "$TMP_DIR/gh-calls.log"; then
    echo "missing expected gh write: $expected" >&2
    exit 1
  fi
done

if [[ "$(grep -c . "$TMP_DIR/gh-args.log")" -ne 11 ]]; then
  echo "expected exactly 11 credential writes" >&2
  exit 1
fi

cat > "$TMP_DIR/expected-gh-args.log" <<'EOF'
variable set DEVELOPER_ID_APPLICATION --env release --repo sonim1/UpdateBar
variable set SPARKLE_PUBLIC_ED_KEY --env release --repo sonim1/UpdateBar
variable set CLOUDFLARE_ACCOUNT_ID --env release --repo sonim1/UpdateBar
secret set APPLE_CERTIFICATE_P12_BASE64 --env release --repo sonim1/UpdateBar
secret set APPLE_CERTIFICATE_PASSWORD --env release --repo sonim1/UpdateBar
secret set APPLE_NOTARY_KEY_P8_BASE64 --env release --repo sonim1/UpdateBar
secret set APPLE_NOTARY_KEY_ID --env release --repo sonim1/UpdateBar
secret set APPLE_NOTARY_ISSUER_ID --env release --repo sonim1/UpdateBar
secret set R2_ACCESS_KEY_ID --env release --repo sonim1/UpdateBar
secret set R2_SECRET_ACCESS_KEY --env release --repo sonim1/UpdateBar
secret set SPARKLE_PRIVATE_ED_KEY --env release --repo sonim1/UpdateBar
EOF
if ! cmp -s "$TMP_DIR/expected-gh-args.log" "$TMP_DIR/gh-args.log"; then
  echo "gh command scopes or order changed" >&2
  diff -u "$TMP_DIR/expected-gh-args.log" "$TMP_DIR/gh-args.log" >&2 || true
  exit 1
fi

if grep -q "sparkle-private\|cert-password\|r2-secret" "$OUTPUT"; then
  echo "script must never print credential values" >&2
  exit 1
fi

# --- only the canonical repository may receive credentials ------------------

for invalid_repo in evil/repo sonim1/UpdateBar-fork; do
  OUTPUT="$TMP_DIR/invalid-repo.out"
  status="$(run_script "$ENV_FILE" "$OUTPUT" GITHUB_REPOSITORY="$invalid_repo")"
  if [[ "$status" -eq 0 ]]; then
    echo "an arbitrary GITHUB_REPOSITORY must be rejected: $invalid_repo" >&2
    exit 1
  fi
  if ! grep -Fq "repository must be exactly sonim1/UpdateBar" "$OUTPUT"; then
    echo "invalid repository failure must name the canonical repository" >&2
    exit 1
  fi
  assert_no_gh_calls "a run with an arbitrary GITHUB_REPOSITORY"
done

ORIGIN_DIR="$TMP_DIR/origin-repo"
mkdir -p "$ORIGIN_DIR"
git -C "$ORIGIN_DIR" init -q
git -C "$ORIGIN_DIR" remote add origin https://github.com/evil/repo.git
OUTPUT="$TMP_DIR/invalid-origin.out"
: > "$TMP_DIR/gh-calls.log"
: > "$TMP_DIR/gh-args.log"
rm -rf "$TMP_DIR/gh-values"
mkdir -p "$TMP_DIR/gh-values"
set +e
(
  cd "$ORIGIN_DIR"
  env -i \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    HOME="$TMP_DIR/home" \
    GH_CALL_LOG="$TMP_DIR/gh-calls.log" \
    GH_ARG_LOG="$TMP_DIR/gh-args.log" \
    GH_VALUE_DIR="$TMP_DIR/gh-values" \
    UPDATEBAR_RELEASE_ENV_FILE="$ENV_FILE" \
    /bin/bash "$SCRIPT"
) > "$OUTPUT" 2>&1
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "an arbitrary git origin must be rejected" >&2
  exit 1
fi
if ! grep -Fq "repository must be exactly sonim1/UpdateBar" "$OUTPUT"; then
  echo "invalid origin failure must name the canonical repository" >&2
  exit 1
fi
assert_no_gh_calls "a run with an arbitrary git origin"

# --- exported values win over the file --------------------------------------

OUTPUT="$TMP_DIR/override.out"
status="$(run_script "$ENV_FILE" "$OUTPUT" CLOUDFLARE_ACCOUNT_ID=exported-account)"
if [[ "$status" -ne 0 ]]; then
  echo "exported override should still upload cleanly" >&2
  exit 1
fi
if ! grep -Fxq "variable CLOUDFLARE_ACCOUNT_ID exported-account" "$TMP_DIR/gh-calls.log"; then
  echo "exported value must win over $ENV_FILE" >&2
  exit 1
fi
# --- a missing value must abort before any upload ---------------------------

missing_name="R2_SECRET_ACCESS_KEY"
PARTIAL_ENV="$TMP_DIR/.env.partial-$missing_name"
grep -v "^${missing_name}=" "$ENV_FILE" > "$PARTIAL_ENV"

OUTPUT="$TMP_DIR/missing-$missing_name.out"
status="$(run_script "$PARTIAL_ENV" "$OUTPUT")"
if [[ "$status" -eq 0 ]]; then
  echo "a missing credential must fail the run: $missing_name" >&2
  exit 1
fi
if ! grep -Fq "missing values: $missing_name" "$OUTPUT"; then
  echo "missing credential must be named in the failure: $missing_name" >&2
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
  exit 1
fi
if ! grep -Fxq "variable SPARKLE_PUBLIC_ED_KEY $VALID_PUBLIC_KEY" "$TMP_DIR/gh-calls.log"; then
  echo "padded public key must be uploaded trimmed" >&2
  exit 1
fi

# --- help stays credential-free ---------------------------------------------

OUTPUT="$TMP_DIR/help.out"
: > "$TMP_DIR/gh-calls.log"
set +e
env -i PATH="$BIN_DIR:/usr/bin:/bin" HOME="$TMP_DIR/home" \
  GH_CALL_LOG="$TMP_DIR/gh-calls.log" GITHUB_REPOSITORY="sonim1/UpdateBar" \
  GH_ARG_LOG="$TMP_DIR/gh-args.log" \
  bash "$SCRIPT" --help > "$OUTPUT" 2>&1
help_status=$?
set -e
if [[ "$help_status" -ne 0 ]]; then
  echo "--help must exit 0" >&2
  exit 1
fi
assert_no_gh_calls "--help"
for help_phrase in \
  "Release environment credentials" \
  "Nothing is uploaded unless every value is" \
  "present and well-formed"; do
  if ! grep -Fq "$help_phrase" "$OUTPUT"; then
    echo "help must document: $help_phrase" >&2
    exit 1
  fi
done

# --- the example file documents credentials and local release settings ------

EXAMPLE_FILE="$ROOT/.env.release.local.example"
if [[ ! -f "$EXAMPLE_FILE" ]]; then
  echo ".env.release.local.example must exist for operators" >&2
  exit 1
fi

required_names="$(grep -oE '^\s*"[A-Z0-9_]+"' "$SCRIPT" | tr -d ' "' | sort -u)"
example_names="$(grep -oE '^[A-Z0-9_]+=' "$EXAMPLE_FILE" | tr -d '=' | sort -u)"
local_setting_names="$(printf '%s\n' \
  NOTARYTOOL_KEYCHAIN_PROFILE \
  SPARKLE_KEY_ACCOUNT \
  R2_BUCKET_NAME \
  UPDATE_DOMAIN \
  CLOUDFLARE_ZONE_ID | sort -u)"
expected_names="$(printf '%s\n%s\n' "$required_names" "$local_setting_names" | sort -u)"
if [[ "$example_names" != "$expected_names" ]]; then
  echo ".env.release.local.example must list exactly the credential and local setting names" >&2
  diff <(printf '%s\n' "$expected_names") <(printf '%s\n' "$example_names") >&2 || true
  exit 1
fi

for local_setting in \
  "NOTARYTOOL_KEYCHAIN_PROFILE=updatebar-notary" \
  "SPARKLE_KEY_ACCOUNT=updatebar" \
  "R2_BUCKET_NAME=updatebar" \
  "UPDATE_DOMAIN=updates.updatebar.royjen.com" \
  "CLOUDFLARE_ZONE_ID="; do
  if ! grep -Fxq "$local_setting" "$EXAMPLE_FILE"; then
    echo ".env.release.local.example must document local setting: $local_setting" >&2
    exit 1
  fi
done

if ! grep -Fxq ".env.release.local" "$ROOT/.gitignore"; then
  echo ".env.release.local must stay untracked" >&2
  exit 1
fi

README_FILE="$ROOT/README.md"
for direct_setup_command in \
  'gh variable set --repo sonim1/UpdateBar VERSION_GITHUB_APP_ID --body "4403130"' \
  'gh secret set --repo sonim1/UpdateBar VERSION_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem' \
  'gh variable set --env release --repo sonim1/UpdateBar TAP_GITHUB_APP_ID --body "4403130"' \
  'gh secret set --env release --repo sonim1/UpdateBar TAP_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem'; do
  if ! grep -Fq "$direct_setup_command" "$README_FILE"; then
    echo "README must document direct GitHub App setup: $direct_setup_command" >&2
    exit 1
  fi
done

# shellcheck disable=SC2016 # Literal Markdown backticks are intentional.
for shared_app_phrase in \
  'sonim1-homebrew-release' \
  '`sonim1/UpdateBar`' \
  '`sonim1/switchtab`' \
  '`sonim1/homebrew-tap`'; do
  if ! grep -Fq "$shared_app_phrase" "$README_FILE"; then
    echo "README must document shared GitHub App scope: $shared_app_phrase" >&2
    exit 1
  fi
done

if grep -Fq 'install it only on' "$README_FILE"; then
  echo "README must not claim the shared GitHub App is tap-only" >&2
  exit 1
fi

echo "setup-release-secrets checks passed"
