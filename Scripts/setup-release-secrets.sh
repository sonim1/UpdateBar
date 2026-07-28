#!/usr/bin/env bash
set -euo pipefail
set +x

TARGET_ENV="release"
ENV_FILE="${UPDATEBAR_RELEASE_ENV_FILE:-.env.release.local}"

REQUIRED_VARS=(
  "DEVELOPER_ID_APPLICATION"
  "SPARKLE_PUBLIC_ED_KEY"
  "CLOUDFLARE_ACCOUNT_ID"
  "TAP_GITHUB_APP_ID"
)
REQUIRED_REPOSITORY_VARS=(
  "VERSION_GITHUB_APP_ID"
)
REQUIRED_SECRETS=(
  "APPLE_CERTIFICATE_P12_BASE64"
  "APPLE_CERTIFICATE_PASSWORD"
  "APPLE_NOTARY_KEY_P8_BASE64"
  "APPLE_NOTARY_KEY_ID"
  "APPLE_NOTARY_ISSUER_ID"
  "R2_ACCESS_KEY_ID"
  "R2_SECRET_ACCESS_KEY"
  "SPARKLE_PRIVATE_ED_KEY"
  "TAP_GITHUB_APP_PRIVATE_KEY"
)
REQUIRED_REPOSITORY_SECRETS=(
  "VERSION_GITHUB_APP_PRIVATE_KEY"
)

usage() {
  cat <<'USAGE'
Usage:
  Scripts/setup-release-secrets.sh

Reads every required release credential from the environment, falling back to
.env.release.local (override with UPDATEBAR_RELEASE_ENV_FILE). Exported values
always win over the file, and the file is never committed.

Repository-scope version App credentials:
  VERSION_GITHUB_APP_ID (public variable)
  VERSION_GITHUB_APP_PRIVATE_KEY (masked secret)
  The contents-write App is installed only on sonim1/UpdateBar.

Release environment credentials (protected `release` environment):
Release environment variables (public, readable in logs):
  DEVELOPER_ID_APPLICATION SPARKLE_PUBLIC_ED_KEY CLOUDFLARE_ACCOUNT_ID
  TAP_GITHUB_APP_ID

Release environment secrets (masked):
  APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD
  APPLE_NOTARY_KEY_P8_BASE64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID
  R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY SPARKLE_PRIVATE_ED_KEY
  TAP_GITHUB_APP_PRIVATE_KEY

Release environment credentials are written under the same names, overwriting
anything already stored there. Version App credentials are written at repository
scope. Nothing is uploaded unless every value is present and well-formed.
USAGE
}

fail() {
  echo "$1" >&2
  exit 1
}

detect_repo() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    printf '%s' "$GITHUB_REPOSITORY"
    return 0
  fi

  local url=""
  url="$(git remote get-url origin 2>/dev/null || true)"
  [[ -n "$url" ]] || return 0

  url="${url%.git}"
  url="${url#https://github.com/}"
  url="${url#ssh://git@github.com/}"
  url="${url#git@github.com:}"
  printf '%s' "$url"
}

# Populates unset variables from a KEY=VALUE file. Existing exports win so the
# file never silently overrides a deliberate one-off override.
load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" == *=* ]] || continue

    key="${line%%=*}"
    value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ "${!key+x}" == x ]] && continue

    if [[ "$value" == \"*\" && "${#value}" -ge 2 ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "${#value}" -ge 2 ]]; then
      value="${value:1:${#value}-2}"
    fi

    printf -v "$key" '%s' "$value"
    export "${key?}"
  done < "$file"
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Rejects the exact malformation that failed the v0.6.3 release: a public key
# that is empty or carries stray whitespace fails app-dmg-smoke-test.sh only
# after signing and notarization have already burned ~40 minutes.
validate_sparkle_public_key() {
  local value="$1"
  if [[ ! "$value" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    fail "SPARKLE_PUBLIC_ED_KEY must be canonical Base64 encoding of exactly 32 bytes"
  fi
}

validate_version_github_app_id() {
  local value="$1"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    fail "VERSION_GITHUB_APP_ID must be canonical positive decimal"
  fi
}

set_repo_variable() {
  local name="$1" value="$2"
  if ! printf '%s' "$value" | gh variable set "$name" \
    --env "$TARGET_ENV" \
    --repo "$REPO" \
    >/dev/null; then
    fail "failed to set variable: $name"
  fi
}

set_repo_secret() {
  local name="$1" value="$2"
  if ! printf '%s' "$value" | gh secret set "$name" \
    --env "$TARGET_ENV" \
    --repo "$REPO" \
    >/dev/null; then
    fail "failed to set secret: $name"
  fi
}

set_repository_variable() {
  local name="$1" value="$2"
  if ! printf '%s' "$value" | gh variable set "$name" \
    --repo "$REPO" \
    >/dev/null; then
    fail "failed to set repository variable: $name"
  fi
}

set_repository_secret() {
  local name="$1" value="$2"
  if ! printf '%s' "$value" | gh secret set "$name" \
    --repo "$REPO" \
    >/dev/null; then
    fail "failed to set repository secret: $name"
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  command -v gh >/dev/null 2>&1 || fail "required command missing: gh"

  REPO="$(detect_repo)"
  [[ -n "$REPO" ]] || fail "unable to detect repository (set GITHUB_REPOSITORY or run in a checked-out repo)"

  load_env_file "$ENV_FILE"

  # Trim only the single-line variables; secrets such as PEM keys are
  # whitespace-significant and must be uploaded byte for byte.
  local name value
  for name in "${REQUIRED_VARS[@]}" "${REQUIRED_REPOSITORY_VARS[@]}"; do
    value="$(trim_whitespace "${!name:-}")"
    printf -v "$name" '%s' "$value"
  done

  local missing=()
  for name in \
    "${REQUIRED_VARS[@]}" \
    "${REQUIRED_REPOSITORY_VARS[@]}" \
    "${REQUIRED_SECRETS[@]}" \
    "${REQUIRED_REPOSITORY_SECRETS[@]}"; do
    [[ -n "${!name:-}" ]] || missing+=("$name")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    fail "missing values: ${missing[*]} (export them or fill in $ENV_FILE)"
  fi

  validate_version_github_app_id "$VERSION_GITHUB_APP_ID"
  validate_sparkle_public_key "$SPARKLE_PUBLIC_ED_KEY"

  for name in "${REQUIRED_VARS[@]}"; do
    set_repo_variable "$name" "${!name}"
    echo "set variable: $name"
  done

  for name in "${REQUIRED_SECRETS[@]}"; do
    set_repo_secret "$name" "${!name}"
    echo "set secret: $name"
  done

  for name in "${REQUIRED_REPOSITORY_VARS[@]}"; do
    set_repository_variable "$name" "${!name}"
    echo "set repository variable: $name"
  done

  for name in "${REQUIRED_REPOSITORY_SECRETS[@]}"; do
    set_repository_secret "$name" "${!name}"
    echo "set repository secret: $name"
  done

  echo "release credentials for env '$TARGET_ENV' and repository-scope version App credentials updated in $REPO"
}

main "$@"
