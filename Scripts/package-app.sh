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
TMP_DIR=""

log() {
  printf "[package-app] %s\n" "$*" >&2
}

sign_app_if_requested() {
  if [[ "${UPDATEBAR_SIGN_APP:-0}" != "1" ]]; then
    return 0
  fi

  local identity="${UPDATEBAR_SIGN_IDENTITY:-}"
  if [[ -z "$identity" ]]; then
    echo "UPDATEBAR_SIGN_APP=1 requires UPDATEBAR_SIGN_IDENTITY" >&2
    exit 1
  fi
  if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign is required for UPDATEBAR_SIGN_APP=1" >&2
    exit 1
  fi

  local options=(
    --force
    --deep
    --options runtime
    --timestamp
  )
  local entitlements="${UPDATEBAR_SIGN_ENTITLEMENTS_FILE:-}"
  if [[ -n "$entitlements" ]]; then
    options+=(--entitlements "$entitlements")
  fi

  log "signing app with identity: ${identity}"
  codesign "${options[@]}" --sign "$identity" "$APP_DIR"
}

notarize_app_if_requested() {
  if [[ "${UPDATEBAR_NOTARIZE_APP:-0}" != "1" ]]; then
    return 0
  fi

  if ! command -v xcrun >/dev/null 2>&1; then
    echo "xcrun is required for UPDATEBAR_NOTARIZE_APP=1" >&2
    exit 1
  fi
  if ! command -v ditto >/dev/null 2>&1; then
    echo "ditto is required for UPDATEBAR_NOTARIZE_APP=1" >&2
    exit 1
  fi

  local keychain_profile="${UPDATEBAR_NOTARYTOOL_KEYCHAIN_PROFILE:-}"
  if [[ -z "$keychain_profile" ]]; then
    echo "UPDATEBAR_NOTARIZE_APP=1 requires UPDATEBAR_NOTARYTOOL_KEYCHAIN_PROFILE" >&2
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  local zip_path="$TMP_DIR/UpdateBar-${VERSION}-macos-arm64.app.zip"

  log "creating notarization archive at $zip_path"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$zip_path"

  log "submitting app for notarization (profile: $keychain_profile)"
  xcrun notarytool submit "$zip_path" --keychain-profile "$keychain_profile" --wait
  log "stapling notarization ticket"
  xcrun stapler staple "$APP_DIR"
}

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
if [[ "$(uname -s)" == "Darwin" ]]; then
  sign_app_if_requested
  notarize_app_if_requested
fi

if [[ "$(uname -s)" == "Darwin" && "${UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE:-0}" != "1" ]]; then
  Scripts/menubar-smoke-test.sh "$APP_DIR"
fi

echo "$APP_DIR"
