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
"$RESOURCES_DIR/updatebar" --version >/dev/null

if [[ "$(uname -s)" == "Darwin" && "${UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE:-0}" != "1" ]]; then
  Scripts/menubar-smoke-test.sh "$APP_DIR"
fi

echo "$APP_DIR"
