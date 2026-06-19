#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source version.env

SWIFT_BIN="${SWIFT_BIN:-swift}"
VERSION="${UPDATEBAR_VERSION:?UPDATEBAR_VERSION is required}"
APP_DIR="dist/UpdateBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

Scripts/generate-version-source.sh
"$SWIFT_BIN" build -c release --product updatebar
"$SWIFT_BIN" build -c release --product updatebar-menubar

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp .build/release/updatebar-menubar "$MACOS_DIR/UpdateBar"
cp .build/release/updatebar "$RESOURCES_DIR/updatebar"
chmod 0755 "$MACOS_DIR/UpdateBar" "$RESOURCES_DIR/updatebar"

cat >"$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>UpdateBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.sonim1.UpdateBar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>UpdateBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
"$RESOURCES_DIR/updatebar" version --json >/dev/null

if [[ "$(uname -s)" == "Darwin" && "${UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE:-0}" != "1" ]]; then
  launch_log="$(mktemp)"
  "$MACOS_DIR/UpdateBar" >"$launch_log" 2>&1 &
  app_pid=$!
  sleep 2
  if ! kill -0 "$app_pid" 2>/dev/null; then
    echo "Packaged menu bar app failed to stay running" >&2
    cat "$launch_log" >&2
    rm -f "$launch_log"
    exit 1
  fi
  if ! grep -F "using bundled updatebar:" "$launch_log" >/dev/null; then
    echo "Packaged menu bar app did not resolve the bundled CLI" >&2
    cat "$launch_log" >&2
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
    rm -f "$launch_log"
    exit 1
  fi
  if grep -F "showing error:" "$launch_log" >/dev/null; then
    echo "Packaged menu bar app reported a startup error" >&2
    cat "$launch_log" >&2
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
    rm -f "$launch_log"
    exit 1
  fi
  kill "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  rm -f "$launch_log"
fi

echo "$APP_DIR"
