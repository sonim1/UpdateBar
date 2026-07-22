#!/usr/bin/env bash
set -euo pipefail
set +x
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 0 ]] || { echo "Usage: Scripts/setup-update-hosting.sh" >&2; exit 64; }

R2_BUCKET_NAME="${R2_BUCKET_NAME:-updatebar-updates}"
UPDATE_DOMAIN="${UPDATE_DOMAIN:-updates.updatebar.sonim1.com}"
WRANGLER_BIN="${WRANGLER_BIN:-$ROOT/node_modules/.bin/wrangler}"
ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
[[ "$R2_BUCKET_NAME" == updatebar-updates && "$UPDATE_DOMAIN" == updates.updatebar.sonim1.com ]] || {
  echo "Update hosting bucket and domain are fixed release contracts" >&2; exit 64;
}
[[ "$ZONE_ID" =~ ^[A-Fa-f0-9]{32}$ ]] || { echo "CLOUDFLARE_ZONE_ID must be a 32-character hexadecimal ID" >&2; exit 64; }
[[ "$ACCOUNT_ID" =~ ^[A-Fa-f0-9]{32}$ ]] || { echo "CLOUDFLARE_ACCOUNT_ID must be a 32-character hexadecimal ID" >&2; exit 64; }
export CLOUDFLARE_ACCOUNT_ID="$ACCOUNT_ID"
[[ -x "$WRANGLER_BIN" ]] || { echo "Pinned local Wrangler is unavailable; run npm ci --ignore-scripts" >&2; exit 66; }

run() {
  local out status
  if out="$("$WRANGLER_BIN" "$@" 2>&1)"; then
    printf '%s\n' "$out"; return 0
  else
    status=$?; printf '%s\n' "$out"; return "$status"
  fi
}

version="$(run --version)" || exit $?
[[ "$version" == 4.112.0 ]] || { echo "Wrangler 4.112.0 is required, got $version" >&2; exit 64; }
if whoami="$(run whoami --json)"; then :; else status=$?; printf '%s\n' "$whoami" >&2; exit "$status"; fi
ruby -rjson -e 'v=JSON.parse(STDIN.read); a=v["accounts"]; id=ARGV[0]; exit(a.is_a?(Array) && a.any?{|x| x.is_a?(Hash) && x["id"]==id} ? 0 : 1)' "$ACCOUNT_ID" <<<"$whoami" || {
  echo "Wrangler authentication output is malformed or has no account" >&2; exit 1;
}

is_absent() {
  local normalized line
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$line" in
      "bucket not found"|"bucket does not exist"|"no such bucket"|"domain not found"|"domain does not exist"|"no such domain") return 0;;
      "the specified bucket does not exist. [code: "*']'|"the specified custom domain does not exist. [code: "*']') return 0;;
    esac
  done <<<"$normalized"
  return 1
}

validate_bucket() {
  ruby -rjson -e 'v=JSON.parse(ARGF.read); exit(v.is_a?(Hash) && v["name"] == "updatebar-updates" ? 0 : 1)' <<<"$1"
}

bucket=""
if bucket="$(run r2 bucket info "$R2_BUCKET_NAME" --json)"; then
  validate_bucket "$bucket" || { echo "Bucket state is malformed or mismatched" >&2; exit 1; }
else
  status=$?
  if ! is_absent "$bucket"; then printf '%s\n' "$bucket" >&2; exit "$status"; fi
  create_status=0; mutation=''
  if mutation="$(run r2 bucket create "$R2_BUCKET_NAME")"; then :; else create_status=$?; fi
  final_bucket_status=0
  if bucket="$(run r2 bucket info "$R2_BUCKET_NAME" --json)"; then
    if validate_bucket "$bucket"; then final_bucket_exact=1; else final_bucket_exact=0; fi
  else
    final_bucket_status=$?; final_bucket_exact=0
  fi
  if [[ "$create_status" != 0 ]]; then
    if [[ "$final_bucket_exact" == 1 ]]; then :; else printf '%s\n' "$mutation" >&2; exit "$create_status"; fi
  elif [[ "$final_bucket_status" != 0 ]]; then
    printf '%s\n' "$bucket" >&2; exit "$final_bucket_status"
  elif [[ "$final_bucket_exact" != 1 ]]; then
    echo "Final bucket state is malformed or mismatched" >&2; exit 1
  fi
fi

validate_domain() {
  ruby -e '
    expected_domain, expected_bucket = ARGV
    values = {}
    STDIN.each_line do |line|
      key, value = line.split(":", 2)
      values[key.strip.downcase] = value.strip if value
    end
    tls = values["min_tls_version"] || values["min tls version"]
    enabled = values["enabled"]
    bucket = values["bucket"]
    ok = values["domain"] == expected_domain && enabled == "Yes" && %w[1.2 1.3].include?(tls)
    ok &&= bucket.nil? || bucket == expected_bucket
    exit(ok ? 0 : 1)
  ' "$UPDATE_DOMAIN" "$R2_BUCKET_NAME" <<<"$1"
}

domain=""
if domain="$(run r2 bucket domain get "$R2_BUCKET_NAME" --domain "$UPDATE_DOMAIN")"; then
  validate_domain "$domain" || { echo "Custom domain state conflicts with the release contract" >&2; exit 1; }
else
  status=$?
  if ! is_absent "$domain"; then printf '%s\n' "$domain" >&2; exit "$status"; fi
  add_status=0; mutation=''
  if mutation="$(run r2 bucket domain add "$R2_BUCKET_NAME" --domain "$UPDATE_DOMAIN" --zone-id "$ZONE_ID" --min-tls 1.2 --force)"; then :; else add_status=$?; fi
  final_domain_status=0
  if domain="$(run r2 bucket domain get "$R2_BUCKET_NAME" --domain "$UPDATE_DOMAIN")"; then
    if validate_domain "$domain"; then final_domain_exact=1; else final_domain_exact=0; fi
  else
    final_domain_status=$?; final_domain_exact=0
  fi
  if [[ "$add_status" != 0 ]]; then
    if [[ "$final_domain_exact" == 1 ]]; then :; else printf '%s\n' "$mutation" >&2; exit "$add_status"; fi
  elif [[ "$final_domain_status" != 0 ]]; then
    printf '%s\n' "$domain" >&2; exit "$final_domain_status"
  elif [[ "$final_domain_exact" != 1 ]]; then
    echo "Final custom domain state is malformed or mismatched" >&2; exit 1
  fi
fi

printf 'https://%s/appcast.xml\n' "$UPDATE_DOMAIN"
