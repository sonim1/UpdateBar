#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-hosting-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
FAKE="$TEST_ROOT/wrangler"
LOG="$TEST_ROOT/calls"
ACCOUNT_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ZONE_ID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

cat >"$FAKE" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >>"$CALL_LOG"
case "$*" in
  "--version") echo "${FAKE_VERSION:-4.112.0}" ;;
  "whoami --json" )
    [[ "${SCENARIO:-}" != unauthorized ]] || { echo denied >&2; exit 23; }
    [[ "${SCENARIO:-}" != account-mismatch ]] || { echo '{"accounts":[{"id":"cccccccccccccccccccccccccccccccc"}]}'; exit 0; }
    echo '{"accounts":[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}' ;;
  "r2 bucket info updatebar-updates --json")
    count_file="${CALL_LOG}.bucket"; count=0; [[ ! -f "$count_file" ]] || count="$(cat "$count_file")"; count=$((count+1)); echo "$count" >"$count_file"
    case "${SCENARIO:-}" in absent) [[ "$count" == 1 ]] && { echo 'Bucket not found' >&2; exit 44; };; race) echo 'Bucket not found' >&2; exit 44;; malformed) echo nope; exit 0;; esac
    echo '{"name":"updatebar-updates"}' ;;
  "r2 bucket create updatebar-updates") [[ "${SCENARIO:-}" == race ]] && exit 45 || echo created ;;
  "r2 bucket domain get updatebar-updates --domain updates.updatebar.sonim1.com")
    count_file="${CALL_LOG}.domain"; count=0; [[ ! -f "$count_file" ]] || count="$(cat "$count_file")"; count=$((count+1)); echo "$count" >"$count_file"
    case "${SCENARIO:-}" in
      absent) [[ "$count" == 1 ]] && { echo 'Domain not found' >&2; exit 44; };;
      final-mismatch) [[ "$count" == 1 ]] && { echo 'Domain not found' >&2; exit 44; }; echo 'domain: wrong.example'; echo 'enabled: Yes'; echo 'min_tls_version: 1.2'; exit 0;;
      conflict) echo 'domain: updates.updatebar.sonim1.com'; echo 'enabled: Yes'; echo 'min_tls_version: 1.2'; echo 'bucket: another'; exit 0;;
      mismatch) echo 'domain: wrong.example'; echo 'enabled: Yes'; echo 'min_tls_version: 1.2'; exit 0;;
      malformed) echo nonsense; exit 0;;
    esac
    echo 'domain: updates.updatebar.sonim1.com'; echo 'enabled: Yes'; echo 'min_tls_version: 1.2'; echo 'bucket: updatebar-updates' ;;
  "r2 bucket domain add updatebar-updates --domain updates.updatebar.sonim1.com --zone-id bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb --min-tls 1.2 --force") echo added ;;
  *) echo "unexpected: $*" >&2; exit 91;;
esac
FAKE
chmod +x "$FAKE"

run_case() {
  local scenario="$1" expected="$2"
  local output="$TEST_ROOT/$scenario.out"
  : >"$LOG"
  rm -f "${LOG}.bucket" "${LOG}.domain"
  set +e
  SCENARIO="$scenario" CALL_LOG="$LOG" WRANGLER_BIN="$FAKE" CLOUDFLARE_ZONE_ID="$ZONE_ID" CLOUDFLARE_ACCOUNT_ID="$ACCOUNT_ID" \
    "$ROOT/Scripts/setup-update-hosting.sh" >"$output" 2>&1
  status=$?
  set -e
  [[ "$status" == "$expected" ]] || { cat "$output" >&2; echo "$scenario: expected $expected got $status" >&2; exit 1; }
}

# RED: implementation does not exist yet.
run_case absent 0
grep -Fq 'https://updates.updatebar.sonim1.com/appcast.xml' "$TEST_ROOT/absent.out"
run_case existing 0
run_case unauthorized 23
run_case account-mismatch 1
run_case conflict 1
run_case malformed 1
run_case mismatch 1
run_case final-mismatch 1
run_case race 45

run_case absent 0
ruby - "$LOG" <<'RUBY'
actual = File.binread(ARGV[0]).split("\0")
expected = %w[
  --version
  whoami --json
  r2 bucket info updatebar-updates --json
  r2 bucket create updatebar-updates
  r2 bucket info updatebar-updates --json
  r2 bucket domain get updatebar-updates --domain updates.updatebar.sonim1.com
  r2 bucket domain add updatebar-updates --domain updates.updatebar.sonim1.com --zone-id bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb --min-tls 1.2 --force
  r2 bucket domain get updatebar-updates --domain updates.updatebar.sonim1.com
]
abort "unexpected Wrangler argv/order:\n#{actual.inspect}" unless actual == expected
RUBY

set +e
SCENARIO=existing FAKE_VERSION=4.111.0 CALL_LOG="$LOG" WRANGLER_BIN="$FAKE" CLOUDFLARE_ZONE_ID="$ZONE_ID" CLOUDFLARE_ACCOUNT_ID="$ACCOUNT_ID" \
  "$ROOT/Scripts/setup-update-hosting.sh" >/dev/null 2>&1
status=$?
set -e
[[ "$status" != 0 ]]

echo "setup update hosting tests passed"
