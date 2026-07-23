#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"

DMG="${1:-}"
HDIUTIL_BIN="${HDIUTIL_BIN:-hdiutil}"
PLUTIL_BIN="${PLUTIL_BIN:-plutil}"
REALPATH_BIN="${REALPATH_BIN:-realpath}"
RUBY_BIN="${RUBY_BIN:-ruby}"
SHASUM_BIN="${SHASUM_BIN:-shasum}"
EXPECTED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
EXPECTED_FEED="${UPDATEBAR_UPDATE_FEED_URL:-https://updates.updatebar.sonim1.com/appcast.xml}"
EXPECTED_NAME="UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg"

TMP_DIR=""
MOUNT_POINT=""
PRIVATE_MOUNT=""
ATTACHED_DEVICE=""
ATTACH_SUCCEEDED=0

fail() {
  echo "$*" >&2
  exit 1
}

cleanup() {
  local original_status=$?
  local detach_status=0
  trap - EXIT HUP INT TERM
  if [[ "$ATTACH_SUCCEEDED" == "1" ]]; then
    set +e
    if [[ -n "$ATTACHED_DEVICE" ]]; then
      "$HDIUTIL_BIN" detach "$ATTACHED_DEVICE" >&2
    else
      "$HDIUTIL_BIN" detach "$PRIVATE_MOUNT" >&2
    fi
    detach_status=$?
    set -e
    ATTACHED_DEVICE=""
    ATTACH_SUCCEEDED=0
    MOUNT_POINT=""
  fi
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" && ! -L "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
  if [[ "$original_status" -eq 0 && "$detach_status" -ne 0 ]]; then
    original_status="$detach_status"
  fi
  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

extract_attached_device() {
  local plist_path="$1"
  "$RUBY_BIN" -e '
    raw = File.binread(ARGV.fetch(0))
    entries = raw.scan(/<key>\s*dev-entry\s*<\/key>\s*<string>([^<]+)<\/string>/m).flatten
    exit 1 if entries.empty?
    bases = entries.map do |entry|
      exit 1 unless entry.match?(%r{\A/dev/disk[0-9]+(?:s[0-9]+)?\z})
      entry.sub(/s[0-9]+\z/, "")
    end.uniq
    exit 1 unless bases.length == 1
    print bases.first
  ' "$plist_path"
}

detach_attachment() {
  [[ "$ATTACH_SUCCEEDED" == "1" ]] || return 0
  if [[ -n "$ATTACHED_DEVICE" ]]; then
    "$HDIUTIL_BIN" detach "$ATTACHED_DEVICE" >&2
  else
    "$HDIUTIL_BIN" detach "$PRIVATE_MOUNT" >&2
  fi
  ATTACHED_DEVICE=""
  ATTACH_SUCCEEDED=0
  MOUNT_POINT=""
}

if [[ -z "$DMG" ]]; then
  fail "usage: Scripts/app-dmg-smoke-test.sh <dmg>"
fi
case "$DMG" in
  /*) ;;
  *) DMG="$PWD/$DMG" ;;
esac
if [[ "$(basename "$DMG")" != "$EXPECTED_NAME" ]]; then
  fail "app DMG must use canonical name $EXPECTED_NAME"
fi
if [[ ! -f "$DMG" || -L "$DMG" ]]; then
  fail "app DMG must be a regular non-symlink file: $DMG"
fi
DMG_REAL="$("$REALPATH_BIN" "$DMG")"
if [[ "$DMG_REAL" != "$DMG" ]]; then
  fail "app DMG path must be canonical and free of symlink or traversal components"
fi
if [[ ! -f "$DMG.sha256" || -L "$DMG.sha256" ]]; then
  fail "missing or unsafe app DMG checksum: $DMG.sha256"
fi

if ! "$RUBY_BIN" -rbase64 -e '
  value = ARGV.fetch(0)
  begin
    bytes = Base64.strict_decode64(value)
    exit(bytes.bytesize == 32 && Base64.strict_encode64(bytes) == value ? 0 : 1)
  rescue ArgumentError
    exit 1
  end
' "$EXPECTED_KEY"; then
  fail "SPARKLE_PUBLIC_ED_KEY must be canonical Base64 encoding of exactly 32 bytes"
fi

RECORDED_SHA="$(awk -v expected="$EXPECTED_NAME" '
  NF == 2 && $1 ~ /^[0-9a-f]{64}$/ && $2 == expected { print $1 }
' "$DMG.sha256")"
if [[ ! "$RECORDED_SHA" =~ ^[0-9a-f]{64}$ ]]; then
  fail "invalid app DMG checksum file: $DMG.sha256"
fi
CALCULATED_SHA="$("$SHASUM_BIN" -a 256 "$DMG" | awk '{print $1}')"
if [[ "$CALCULATED_SHA" != "$RECORDED_SHA" ]]; then
  fail "app DMG checksum mismatch: $DMG"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-dmg-smoke.XXXXXX")"
ATTACH_PLIST="$TMP_DIR/attach.plist"
ATTACH_JSON="$TMP_DIR/attach.json"
PRIVATE_MOUNT="$TMP_DIR/mount"
mkdir "$PRIVATE_MOUNT"
PRIVATE_MOUNT="$("$REALPATH_BIN" "$PRIVATE_MOUNT")"
"$HDIUTIL_BIN" attach -mountpoint "$PRIVATE_MOUNT" -plist -nobrowse -readonly "$DMG" >"$ATTACH_PLIST"
ATTACH_SUCCEEDED=1
ATTACHED_DEVICE="$(extract_attached_device "$ATTACH_PLIST")" || ATTACHED_DEVICE=""
"$PLUTIL_BIN" -convert json -o "$ATTACH_JSON" "$ATTACH_PLIST"
MOUNT_POINT="$("$RUBY_BIN" -rjson -e '
  document = JSON.parse(File.binread(ARGV.fetch(0)))
  entities = document.is_a?(Array) ? document : document.fetch("system-entities", [])
  values = entities.each_with_object([]) do |entity, result|
    result << entity["mount-point"] if entity.is_a?(Hash) && entity.key?("mount-point")
  end
  valid = values.length == 1 && values.first.is_a?(String) && values.first.start_with?("/") &&
    !values.first.include?("\0") && !values.first.include?("\n") && !values.first.include?("\r")
  exit 1 unless valid
  print values.first
' "$ATTACH_JSON")" || fail "unable to identify exactly one safe DMG mount point"
MOUNT_REAL="$("$REALPATH_BIN" "$MOUNT_POINT")"
if [[ "$MOUNT_POINT" != "$PRIVATE_MOUNT" || "$MOUNT_REAL" != "$PRIVATE_MOUNT" ]]; then
  fail "DMG did not mount at its private requested mount point"
fi
APP="$MOUNT_POINT/UpdateBar.app"
APPLICATIONS_LINK="$MOUNT_POINT/Applications"
if [[ ! -d "$APP" || -L "$APP" ]]; then
  fail "mounted DMG is missing a safe UpdateBar.app"
fi
APP_REAL="$("$REALPATH_BIN" "$APP")"
case "$APP_REAL" in
  "$MOUNT_REAL"/*) ;;
  *) fail "UpdateBar.app resolves outside the mounted DMG" ;;
esac
if [[ ! -L "$APPLICATIONS_LINK" || "$(readlink "$APPLICATIONS_LINK")" != "/Applications" ]]; then
  fail "mounted DMG must contain Applications -> /Applications"
fi

INFO_PLIST="$APP/Contents/Info.plist"
APP_EXECUTABLE="$APP/Contents/MacOS/UpdateBar"
CLI_EXECUTABLE="$APP/Contents/Resources/updatebar"
APP_ICON="$APP/Contents/Resources/UpdateBar.icns"
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
if [[ ! -f "$INFO_PLIST" || -L "$INFO_PLIST" ]]; then
  fail "mounted app is missing a safe Info.plist"
fi
if [[ ! -f "$APP_EXECUTABLE" || -L "$APP_EXECUTABLE" || ! -x "$APP_EXECUTABLE" ]]; then
  fail "mounted app is missing an executable UpdateBar binary"
fi
if [[ ! -f "$CLI_EXECUTABLE" || -L "$CLI_EXECUTABLE" || ! -x "$CLI_EXECUTABLE" ]]; then
  fail "mounted app is missing an executable bundled CLI"
fi
if [[ ! -f "$APP_ICON" || -L "$APP_ICON" ]]; then
  fail "mounted app is missing a safe app icon"
fi
if [[ ! -d "$SPARKLE_FRAMEWORK" || -L "$SPARKLE_FRAMEWORK" ]]; then
  fail "mounted app is missing a safe Sparkle.framework"
fi
for path in "$INFO_PLIST" "$APP_EXECUTABLE" "$CLI_EXECUTABLE" "$APP_ICON" "$SPARKLE_FRAMEWORK"; do
  resolved="$("$REALPATH_BIN" "$path")"
  case "$resolved" in
    "$APP_REAL"/*) ;;
    *) fail "mounted app content resolves outside UpdateBar.app: $path" ;;
  esac
done

plist_value() {
  "$PLUTIL_BIN" -extract "$1" raw -o - "$INFO_PLIST"
}

BUNDLE_ID="$(plist_value CFBundleIdentifier)"
PLIST_EXECUTABLE="$(plist_value CFBundleExecutable)"
PLIST_ICON="$(plist_value CFBundleIconFile)"
PACKAGE_TYPE="$(plist_value CFBundlePackageType)"
LSUI_ELEMENT="$(plist_value LSUIElement)"
APP_VERSION="$(plist_value CFBundleShortVersionString)"
APP_BUILD="$(plist_value CFBundleVersion)"
APP_FEED="$(plist_value SUFeedURL)"
APP_KEY="$(plist_value SUPublicEDKey)"
if [[ "$BUNDLE_ID" != "com.sonim1.UpdateBar" ]]; then
  fail "unexpected app bundle identifier: ${BUNDLE_ID:-missing}"
fi
if [[ "$PLIST_EXECUTABLE" != "UpdateBar" ]]; then
  fail "app DMG has an unexpected CFBundleExecutable"
fi
if [[ "$PLIST_ICON" != "UpdateBar.icns" ]]; then
  fail "app DMG has an unexpected CFBundleIconFile"
fi
if [[ "$PACKAGE_TYPE" != "APPL" ]]; then
  fail "app DMG has an unexpected CFBundlePackageType"
fi
if [[ "$LSUI_ELEMENT" != "true" && "$LSUI_ELEMENT" != "1" ]]; then
  fail "app DMG must set LSUIElement to true"
fi
if [[ "$APP_VERSION" != "$UPDATEBAR_VERSION" ]]; then
  fail "app DMG version mismatch: ${APP_VERSION:-missing}"
fi
if [[ ! "$APP_BUILD" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  fail "app DMG has an invalid bundle build: ${APP_BUILD:-missing}"
fi
if [[ "$APP_FEED" != "$EXPECTED_FEED" ]]; then
  fail "app DMG has an unexpected Sparkle feed URL"
fi
if [[ "$APP_KEY" != "$EXPECTED_KEY" ]]; then
  fail "app DMG has an unexpected Sparkle public key"
fi
CLI_VERSION="$($CLI_EXECUTABLE --version)"
if [[ "$CLI_VERSION" != "$UPDATEBAR_VERSION" ]]; then
  fail "app DMG bundled CLI version mismatch"
fi

detach_attachment
trap - EXIT
rm -rf "$TMP_DIR"
TMP_DIR=""
echo "app DMG smoke ok"
