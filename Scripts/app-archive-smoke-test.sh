#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${1:-}"

if [[ -z "$ARCHIVE" ]]; then
  if [[ ! -d "$ROOT/dist/UpdateBar.app" ]]; then
    UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 "$ROOT/Scripts/package-app.sh" >/dev/null
  fi
  ARCHIVE="$("$ROOT/Scripts/build-app-archive.sh" | tail -n 1)"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR"

APP_DIR="$TMP_DIR/UpdateBar.app"
MACOS_BIN="$APP_DIR/Contents/MacOS/UpdateBar"
CLI_BIN="$APP_DIR/Contents/Resources/updatebar"
INFO_PLIST="$APP_DIR/Contents/Info.plist"

if [[ ! -x "$MACOS_BIN" ]]; then
  echo "missing executable menu bar binary: $MACOS_BIN" >&2
  exit 1
fi
if [[ ! -x "$CLI_BIN" ]]; then
  echo "missing executable bundled CLI: $CLI_BIN" >&2
  exit 1
fi
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "missing Info.plist: $INFO_PLIST" >&2
  exit 1
fi

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$INFO_PLIST" >/dev/null
fi
"$CLI_BIN" --version >/dev/null

echo "app archive smoke ok"
