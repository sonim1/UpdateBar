#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "menubar-smoke-test is only supported on macOS"
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="${1:-dist/UpdateBar.app}"
BIN_PATH="$APP_PATH/Contents/MacOS/UpdateBar"
RES_PATH="$APP_PATH/Contents/Resources/updatebar"
LOG_PATH="$HOME/Library/Logs/UpdateBar/updatebar-menubar.log"

if [[ ! -x "$BIN_PATH" ]]; then
    echo "app binary missing: $BIN_PATH"
    echo "build with: Scripts/package-app.sh"
    exit 1
fi

if [[ ! -x "$RES_PATH" ]]; then
    echo "bundled CLI missing: $RES_PATH"
    echo "build with: Scripts/package-app.sh"
    exit 1
fi

tmp_log="$(mktemp)"
trap 'kill "$MENUBAR_PID" 2>/dev/null || true; wait "$MENUBAR_PID" 2>/dev/null || true; rm -f "$tmp_log"' EXIT

echo "launching $APP_PATH"
"$BIN_PATH" >"$tmp_log" 2>&1 &
MENUBAR_PID=$!

sleep 2

if ! kill -0 "$MENUBAR_PID" 2>/dev/null; then
    echo "menu bar process exited immediately"
    cat "$tmp_log"
    exit 1
fi

if ! grep -F "UpdateBarMenuBar main starting" "$tmp_log" >/dev/null; then
    echo "missing startup marker in launch log"
    cat "$tmp_log"
    exit 1
fi

if ! grep -F "using" "$tmp_log" | grep -F "updatebar" >/dev/null; then
    echo "missing CLI resolution log line"
    cat "$tmp_log"
    exit 1
fi

if grep -F "showing error" "$tmp_log" >/dev/null; then
    echo "menu bar reported startup error"
    cat "$tmp_log"
    exit 1
fi

echo "menu bar launch smoke passed"
echo "runtime log target: $LOG_PATH"
echo "runtime log tail:"
if [[ -f "$LOG_PATH" ]]; then
    tail -n 20 "$LOG_PATH"
fi
