#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UPDATEBAR_BIN="${UPDATEBAR_BIN:-}"
RUNNER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-updatebar.sh"
CREATED_TMP_HOME=0
if [[ -z "${TMP_HOME:-}" ]]; then
  TMP_HOME="$(mktemp -d)"
  CREATED_TMP_HOME=1
fi
export UPDATEBAR_HOME="$TMP_HOME"
cleanup() {
  if [[ "$CREATED_TMP_HOME" == "1" ]]; then
    rm -rf "$TMP_HOME"
  fi
}
trap cleanup EXIT

run_case() {
  local name="$1"
  local expected_rc="$2"
  shift 2
  local output rc

  printf "\n[CASE] %s\n" "$name"
  set +e
  output=$({ "$RUNNER" "$@" 2>&1; })
  rc=$?
  set -e
  printf "%s\n" "$output"
  printf "exit=%s\n" "$rc"

  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "Expected exit code $expected_rc, got $rc" >&2
    return 1
  fi
}

run_case_fail() {
  run_case "$1" 1 "${@:2}"
}

run_case_ok() {
  run_case "$1" 0 "${@:2}"
}

run_case_contains() {
  local name="$1"
  local expected_rc="$2"
  local expected_text="$3"
  shift 3
  local output rc

  printf "\n[CASE] %s\n" "$name"
  set +e
  output=$({ "${RUNNER[@]}" "$@" 2>&1; })
  rc=$?
  set -e
  printf "%s\n" "$output"
  printf "exit=%s\n" "$rc"

  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "Expected exit code $expected_rc, got $rc" >&2
    return 1
  fi
  if [[ "$output" != *"$expected_text"* ]]; then
    echo "Expected output to contain: $expected_text" >&2
    return 1
  fi
}

run_case_empty_home() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "[CASE] background status (non-macOS) skipped"
    return 0
  fi
  local name="$1"
  shift
  local output rc

  printf "\n[CASE] %s\n" "$name"
  set +e
  output=$({ HOME="$TMP_HOME" "$RUNNER" "$@" 2>&1; })
  rc=$?
  set -e
  printf "%s\n" "$output"
  printf "exit=%s\n" "$rc"

  if [[ "$rc" -ne 0 ]]; then
    echo "Expected exit code 0, got $rc" >&2
    return 1
  fi
  if [[ "$output" != *"\"path\":\"$TMP_HOME/Library/LaunchAgents/com.updatebar.check.plist\""* ]]; then
    echo "background status did not use isolated HOME" >&2
    return 1
  fi
}

run_case_background_install_from_path() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "[CASE] background install from PATH (non-macOS) skipped"
    return 0
  fi
  if [[ -z "$UPDATEBAR_BIN" ]]; then
    echo "[CASE] background install from PATH skipped without UPDATEBAR_BIN"
    return 0
  fi

  local bin_dir target plist output rc
  bin_dir="$TMP_HOME/bin"
  mkdir -p "$bin_dir"
  case "$UPDATEBAR_BIN" in
    /*) target="$UPDATEBAR_BIN" ;;
    *) target="$PWD/$UPDATEBAR_BIN" ;;
  esac
  ln -sf "$target" "$bin_dir/updatebar"
  plist="$TMP_HOME/Library/LaunchAgents/com.updatebar.check.plist"

  printf "\n[CASE] background install from PATH\n"
  set +e
  output=$(PATH="$bin_dir:/usr/bin:/bin" HOME="$TMP_HOME" UPDATEBAR_HOME="$TMP_HOME" updatebar background install --yes --json 2>&1)
  rc=$?
  set -e
  printf "%s\n" "$output"
  printf "exit=%s\n" "$rc"

  if [[ "$rc" -ne 0 ]]; then
    echo "Expected exit code 0, got $rc" >&2
    return 1
  fi
  if [[ ! -f "$plist" ]]; then
    echo "Expected LaunchAgent plist at $plist" >&2
    return 1
  fi
  if ! grep -F "<string>$bin_dir/updatebar</string>" "$plist" >/dev/null; then
    echo "LaunchAgent plist did not store resolved PATH executable" >&2
    cat "$plist" >&2
    return 1
  fi
}

# Positive flow: import baseline fixture via stdin, then list and status.
run_case_ok "import from stdin" import - < Fixtures/manifests/valid-basic.json
run_case_contains "approvals include command text" 0 '"command":' approvals claude-code --json
mkdir -p "$TMP_HOME/work"
CWD_RECIPE="$TMP_HOME/cwd-recipe.json"
cat >"$CWD_RECIPE" <<JSON
{
  "id": "cwd-tool",
  "name": "Cwd Tool",
  "category": "cli",
  "path": null,
  "source": { "kind": "custom", "ref": "cwd-tool", "branch": null },
  "version_scheme": "semver",
  "check": { "cmd": "printf 1.0.0" },
  "latest": { "strategy": "cmd", "cmd": "printf 1.0.1", "pattern": null },
  "version_parse": { "regex": "([0-9]+\\\\.[0-9]+\\\\.[0-9]+)" },
  "update": {
    "cmd": "printf updated",
    "requires_write": true,
    "cwd": "$TMP_HOME/work"
  },
  "pin": null,
  "enabled": true,
  "notify": true,
  "trust": { "level": "untrusted", "approved_commands": {} }
}
JSON
run_case_ok "add cwd fixture" add --from "$CWD_RECIPE"
run_case_contains "approvals include update cwd" 0 '"cwd":' approvals cwd-tool --json
run_case_fail "duplicate import should fail" import Fixtures/manifests/valid-basic.json
run_case_ok "add fixture from file with replace" add --from Fixtures/manifests/untrusted-import.json --replace
run_case_fail "duplicate add should fail" add --from Fixtures/manifests/untrusted-import.json
run_case_fail "validate invalid manifest should fail" validate Fixtures/manifests/invalid-missing-required.json --json
run_case_ok "validate stdin should pass" validate - --json < Fixtures/manifests/valid-basic.json
run_case_fail "approve non-command field should fail" approve claude-code --field latest.cmd --json
run_case_fail "config set unknown key should fail" config set provider.default local
run_case_ok "config set known key" config set security.require_https_source false
run_case_ok "config get known key" config get security.require_https_source
run_case_fail "remove missing item should fail" remove missing-item --yes
run_case_empty_home "background status (macOS only)" background status --json
run_case_background_install_from_path

printf "\nE2E edgecase checks complete\n"
