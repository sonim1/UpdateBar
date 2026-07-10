#!/usr/bin/env bash
set -euo pipefail

# Regression test for TUI keyboard input. Drives `updatebar tui` in a real
# PTY and asserts that a down-arrow moves the menu cursor. Guards against
# raw-mode regressions such as spawning the TUI in a background process
# group, where arrow keys echo as escape sequences instead of navigating.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v expect >/dev/null 2>&1; then
  echo "expect not installed; skipping tui input test" >&2
  exit 0
fi
if ! command -v node >/dev/null 2>&1; then
  echo "node not installed; skipping tui input test" >&2
  exit 0
fi

SWIFT_BIN="${SWIFT_BIN:-swift}"
BIN="${UPDATEBAR_BIN:-}"
if [[ -z "$BIN" || ! -x "$BIN" ]]; then
  "$SWIFT_BIN" build --product updatebar >&2
  BIN="$ROOT/.build/debug/updatebar"
fi

if [[ ! -f "tui/dist/index.js" ]]; then
  npm --prefix tui install >&2
  npm --prefix tui run build >&2
fi
chmod 755 tui/dist/index.js

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

EXPECT_SCRIPT="$TMP_DIR/drive.exp"
cat >"$EXPECT_SCRIPT" <<'EXPECT'
set timeout 20
spawn $env(TUI_TEST_BIN) tui
expect {
    "navigate" {}
    timeout { puts "TUI-INPUT-FAIL: menu never rendered"; exit 1 }
}
send "\x1b\[B"
expect {
    "› Scan & Add" { puts "TUI-INPUT-OK" }
    timeout { puts "TUI-INPUT-FAIL: arrow key did not move the cursor"; exit 1 }
}
send "q"
sleep 1
close
catch wait
exit 0
EXPECT

OUTPUT="$TMP_DIR/session.log"
if ! env \
  TUI_TEST_BIN="$BIN" \
  UPDATEBAR_HOME="$TMP_DIR/home" \
  UPDATEBAR_TUI="$ROOT/tui/dist/index.js" \
  expect "$EXPECT_SCRIPT" >"$OUTPUT" 2>&1; then
  echo "tui input test failed" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "TUI-INPUT-OK" "$OUTPUT"; then
  echo "tui input test did not confirm navigation" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

echo "tui input behavior ok"
