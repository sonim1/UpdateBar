#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"
ARCHIVE="${1:-}"

if [[ -z "$ARCHIVE" ]]; then
  if [[ ! -d "$ROOT/dist/UpdateBar.app" ]]; then
    UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 "$ROOT/Scripts/package-app.sh" >/dev/null
  fi
  ARCHIVE="$("$ROOT/Scripts/build-app-archive.sh")"
fi

if [[ -f "${ARCHIVE}.sha256" ]]; then
  "$ROOT/Scripts/verify-archive-checksum.sh" "$ARCHIVE"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR"

APP_DIR="$TMP_DIR/UpdateBar.app"
MACOS_BIN="$APP_DIR/Contents/MacOS/UpdateBar"
CLI_BIN="$APP_DIR/Contents/Resources/updatebar"
INFO_PLIST="$APP_DIR/Contents/Info.plist"

plist_value() {
  local key="$1"
  if command -v plutil >/dev/null 2>&1; then
    plutil -extract "$key" raw "$INFO_PLIST" 2>/dev/null || true
    return
  fi
  awk -v key="$key" '
    $0 ~ "<key>" key "</key>" {
      getline
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      gsub(/<string>|<\/string>/, "")
      print
      exit
    }
  ' "$INFO_PLIST"
}

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

APP_EXECUTABLE="$(plist_value CFBundleExecutable)"
if [[ "$APP_EXECUTABLE" != "UpdateBar" ]]; then
  echo "app archive has unexpected executable name: $ARCHIVE" >&2
  echo "  expected: UpdateBar" >&2
  echo "  actual:   ${APP_EXECUTABLE:-missing}" >&2
  exit 1
fi

PACKAGE_TYPE="$(plist_value CFBundlePackageType)"
if [[ "$PACKAGE_TYPE" != "APPL" ]]; then
  echo "app archive is not a double-clickable app bundle: $ARCHIVE" >&2
  echo "  expected CFBundlePackageType: APPL" >&2
  echo "  actual:                       ${PACKAGE_TYPE:-missing}" >&2
  exit 1
fi

BUNDLE_IDENTIFIER="$(plist_value CFBundleIdentifier)"
if [[ "$BUNDLE_IDENTIFIER" != "com.sonim1.UpdateBar" ]]; then
  echo "app archive has unexpected bundle identifier: $ARCHIVE" >&2
  echo "  expected: com.sonim1.UpdateBar" >&2
  echo "  actual:   ${BUNDLE_IDENTIFIER:-missing}" >&2
  exit 1
fi

LSUI_ELEMENT="$(plist_value LSUIElement)"
if [[ "$LSUI_ELEMENT" != "true" && "$LSUI_ELEMENT" != "1" && "$LSUI_ELEMENT" != "<true/>" ]]; then
  echo "app archive is not configured as a menu bar app: $ARCHIVE" >&2
  echo "  expected LSUIElement true" >&2
  echo "  actual:   ${LSUI_ELEMENT:-missing}" >&2
  exit 1
fi

APP_VERSION="$(plist_value CFBundleShortVersionString)"
if [[ "$APP_VERSION" != "$UPDATEBAR_VERSION" ]]; then
  echo "app archive version mismatch for $ARCHIVE" >&2
  echo "  expected: $UPDATEBAR_VERSION" >&2
  echo "  actual:   ${APP_VERSION:-missing}" >&2
  exit 1
fi

CLI_VERSION="$("$CLI_BIN" --version)"
if [[ "$CLI_VERSION" != "$UPDATEBAR_VERSION" ]]; then
  echo "app archive bundled CLI version mismatch for $ARCHIVE" >&2
  echo "  expected: $UPDATEBAR_VERSION" >&2
  echo "  actual:   $CLI_VERSION" >&2
  exit 1
fi

echo "app archive smoke ok"
