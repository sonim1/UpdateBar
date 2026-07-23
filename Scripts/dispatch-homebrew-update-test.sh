#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; SOURCE="$ROOT/Scripts/dispatch-homebrew-update.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ -x "$SOURCE" ]] || fail "dispatch-homebrew-update.sh is missing or not executable"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-dispatch-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
GH="$TMP/gh"; LOG="$TMP/log"; TOKEN='tap-secret-sentinel'
cat >"$GH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'call\n' >>"$GH_LOG"
[[ "${GH_TOKEN:-}" == "$EXPECTED_TOKEN" && -z "${TAP_GH_TOKEN:-}" ]] || exit 80
[[ "${GH_HOST:-}" == github.com && "${GH_REPO:-}" == sonim1/homebrew-tap ]] || exit 81
expected=(api --hostname github.com --method POST repos/sonim1/homebrew-tap/dispatches -f event_type=homebrew_release -f 'client_payload[repository]=sonim1/UpdateBar' -f 'client_payload[tag]=v1.2.3')
[[ $# == "${#expected[@]}" ]] || exit 82
i=0; for arg in "$@"; do [[ "$arg" == "${expected[$i]}" ]] || exit 83; i=$((i+1)); done
exit "${FAKE_STATUS:-0}"
EOF
chmod +x "$GH"; : >"$LOG"
run(){ set +e; output="$(GH_BIN="$GH" GH_LOG="$LOG" EXPECTED_TOKEN="$TOKEN" TAP_GH_TOKEN="${TEST_TOKEN-$TOKEN}" GH_HOST=evil.invalid GH_REPO=evil/repo FAKE_STATUS="${FAKE_STATUS:-0}" "$SOURCE" "$@" 2>&1)"; status=$?; set -e; }
run v1.2.3; [[ "$status" == 0 && "$(wc -l <"$LOG"|tr -d ' ')" == 1 && "$output" != *"$TOKEN"* ]] || fail "valid dispatch failed/leaked: $status $output"
: >"$LOG"; FAKE_STATUS=37; run v1.2.3; [[ "$status" == 37 && "$(wc -l <"$LOG"|tr -d ' ')" == 1 ]] || fail "failure was retried or translated"
FAKE_STATUS=0
for value in '' '1.2.3' v v1. v1..2 v1.2-beta 'v1.2;bad'; do : >"$LOG"; if [[ -z "$value" ]]; then run; else run "$value"; fi; [[ "$status" == 64 && ! -s "$LOG" ]] || fail "unsafe tag accepted: $value ($status $output)"; done
: >"$LOG"; run v1.2.3 extra; [[ "$status" == 64 && ! -s "$LOG" ]] || fail "extra argument accepted"
: >"$LOG"; TEST_TOKEN=''; run v1.2.3; [[ "$status" == 64 && ! -s "$LOG" ]] || fail "empty token accepted"; unset TEST_TOKEN
: >"$LOG"; set +e; output="$(GH_BIN="$GH" GH_LOG="$LOG" EXPECTED_TOKEN="$TOKEN" TAP_GH_TOKEN="$TOKEN" GH_HOST=evil.invalid GH_REPO=evil/repo bash -x "$SOURCE" v1.2.3 2>&1)"; status=$?; set -e
[[ "$status" == 0 && "$output" != *"$TOKEN"* && "$(wc -l <"$LOG"|tr -d ' ')" == 1 ]] || fail "xtrace leaked or changed dispatch"
bash -n "$SOURCE" "$0"; echo "dispatch-homebrew-update contract tests passed"
