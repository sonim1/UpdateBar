#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source version.env

SWIFT_BIN="${SWIFT_BIN:-swift}"
DITTO_BIN="${DITTO_BIN:-ditto}"
PLUTIL_BIN="${PLUTIL_BIN:-plutil}"
CODESIGN_BIN="${CODESIGN_BIN:-codesign}"
OTOOL_BIN="${OTOOL_BIN:-otool}"
FIND_BIN="${FIND_BIN:-find}"
REALPATH_BIN="${REALPATH_BIN:-realpath}"
RUBY_BIN="${RUBY_BIN:-ruby}"
VERSION="${UPDATEBAR_VERSION:?UPDATEBAR_VERSION is required}"
UPDATE_FEED_URL="${UPDATEBAR_UPDATE_FEED_URL-https://updates.updatebar.sonim1.com/appcast.xml}"
SPARKLE_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

APP_DIR="dist/UpdateBar.app"
STAGING_APP_DIR="dist/.UpdateBar.app.tmp.$$"
CONTENTS_DIR="$STAGING_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ICON_SOURCE="$ROOT/Assets/AppIcon/UpdateBar.icns"
SPARKLE_ARTIFACT_ROOT="$ROOT/.build/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK_SOURCE=""

log() {
  printf "[package-app] %s\n" "$*" >&2
}

fail() {
  echo "$*" >&2
  exit 1
}

invalid_release_metadata() {
  echo "$*" >&2
  exit 64
}

require_command() {
  local command_name="$1"
  local purpose="$2"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "$command_name is required to $purpose"
  fi
}

validate_inputs() {
  local validation_status=0
  require_command "$RUBY_BIN" "validate Sparkle release metadata"

  "$RUBY_BIN" -ruri -e '
    value = ARGV.fetch(0)
    printable_ascii = value.ascii_only? && value.bytes.all? { |byte| byte >= 0x21 && byte <= 0x7e }
    begin
      uri = URI.parse(value)
      valid = printable_ascii && uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty? && uri.userinfo.nil?
      exit(valid ? 0 : 64)
    rescue URI::Error
      exit 64
    end
  ' "$UPDATE_FEED_URL" || {
    validation_status=$?
    if [[ "$validation_status" == "64" ]]; then
      invalid_release_metadata "UPDATEBAR_UPDATE_FEED_URL must be a printable ASCII HTTPS URL without whitespace, control characters, or user info"
    fi
    return "$validation_status"
  }

  "$RUBY_BIN" -rbase64 -e '
    value = ARGV.fetch(0)
    begin
      decoded = Base64.strict_decode64(value)
      valid = decoded.bytesize == 32 && Base64.strict_encode64(decoded) == value
      exit(valid ? 0 : 64)
    rescue ArgumentError
      exit 64
    end
  ' "$SPARKLE_ED_KEY" || {
    validation_status=$?
    if [[ "$validation_status" == "64" ]]; then
      invalid_release_metadata "SPARKLE_PUBLIC_ED_KEY must be canonical Base64 encoding of exactly 32 bytes"
    fi
    return "$validation_status"
  }

  if [[ "${UPDATEBAR_SIGN_APP:-0}" == "1" ]]; then
    SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-${UPDATEBAR_SIGN_IDENTITY:-}}"
    if [[ -z "$SIGN_IDENTITY" ]]; then
      fail "UPDATEBAR_SIGN_APP=1 requires DEVELOPER_ID_APPLICATION (UPDATEBAR_SIGN_IDENTITY is supported as a compatibility fallback)"
    fi
    require_command "$CODESIGN_BIN" "sign the app"
  else
    SIGN_IDENTITY=""
  fi

  [[ -f "$ICON_SOURCE" && ! -L "$ICON_SOURCE" ]] || fail "missing app icon: $ICON_SOURCE"
  require_command "$SWIFT_BIN" "build UpdateBar"
  require_command "$DITTO_BIN" "copy Sparkle.framework"
  require_command "$PLUTIL_BIN" "generate Info.plist"
  require_command "$OTOOL_BIN" "validate the packaged executable"
  require_command "$FIND_BIN" "locate Sparkle.framework"
  require_command "$REALPATH_BIN" "validate Sparkle.framework symlinks"
}

discover_sparkle_framework() {
  local candidate=""
  local candidate_list=""
  local candidate_count=0
  local slice=""
  local architectures=""

  [[ -d "$SPARKLE_ARTIFACT_ROOT" && ! -L "$SPARKLE_ARTIFACT_ROOT" ]] || \
    fail "expected exactly one compatible macOS Sparkle.framework under $SPARKLE_ARTIFACT_ROOT; found 0"

  candidate_list="$(mktemp "${TMPDIR:-/tmp}/updatebar-sparkle-frameworks.XXXXXX")"
  "$FIND_BIN" "$SPARKLE_ARTIFACT_ROOT" -type d -name Sparkle.framework -print0 >"$candidate_list" || {
    local find_status=$?
    rm -f "$candidate_list"
    return "$find_status"
  }
  while IFS= read -r -d '' candidate; do
    [[ ! -L "$candidate" ]] || continue
    slice="$(basename "$(dirname "$candidate")")"
    case "$slice" in
      macos-*) ;;
      *) continue ;;
    esac
    architectures="${slice#macos-}"
    case "_${architectures}_" in
      *"_${ARCH}_"*) ;;
      *) continue ;;
    esac
    SPARKLE_FRAMEWORK_SOURCE="$candidate"
    candidate_count=$((candidate_count + 1))
  done <"$candidate_list"
  rm -f "$candidate_list"

  if [[ "$candidate_count" != "1" ]]; then
    fail "expected exactly one compatible macOS Sparkle.framework under $SPARKLE_ARTIFACT_ROOT; found $candidate_count"
  fi
}

validate_framework_symlinks() {
  local framework="$FRAMEWORKS_DIR/Sparkle.framework"
  local link=""
  local link_list=""
  local resolved=""
  local framework_resolved=""

  framework_resolved="$("$REALPATH_BIN" "$framework")"
  link_list="$(mktemp "${TMPDIR:-/tmp}/updatebar-sparkle-links.XXXXXX")"
  "$FIND_BIN" "$framework" -type l -print0 >"$link_list" || {
    local find_status=$?
    rm -f "$link_list"
    return "$find_status"
  }
  while IFS= read -r -d '' link; do
    resolved="$("$REALPATH_BIN" "$link")" || fail "unsafe or broken Sparkle.framework symlink: $link"
    case "$resolved" in
      "$framework_resolved"/*) ;;
      *) fail "Sparkle.framework symlink resolves outside the copied framework: $link" ;;
    esac
  done <"$link_list"
  rm -f "$link_list"
}

require_regular_file() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || fail "missing or unsafe signing target: $path"
}

require_bundle_directory() {
  local path="$1"
  [[ -d "$path" && ! -L "$path" ]] || fail "missing or unsafe signing target: $path"
}

validate_signing_targets() {
  local framework="$FRAMEWORKS_DIR/Sparkle.framework"
  require_regular_file "$framework/Versions/B/Autoupdate"
  require_bundle_directory "$framework/Versions/B/Updater.app"
  require_regular_file "$framework/Versions/B/Updater.app/Contents/MacOS/Updater"
  require_bundle_directory "$framework/Versions/B/XPCServices/Downloader.xpc"
  require_regular_file "$framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
  require_bundle_directory "$framework/Versions/B/XPCServices/Installer.xpc"
  require_regular_file "$framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  require_bundle_directory "$framework"
  require_regular_file "$RESOURCES_DIR/updatebar"
  require_regular_file "$MACOS_DIR/UpdateBar"
  require_bundle_directory "$STAGING_APP_DIR"
}

sign_app_if_requested() {
  if [[ "${UPDATEBAR_SIGN_APP:-0}" != "1" ]]; then
    return 0
  fi

  validate_signing_targets

  local options=(
    --force
    --options runtime
    --timestamp
  )
  local entitlements="${UPDATEBAR_SIGN_ENTITLEMENTS_FILE:-}"
  if [[ -n "$entitlements" ]]; then
    options+=(--entitlements "$entitlements")
  fi

  local framework="$FRAMEWORKS_DIR/Sparkle.framework"
  log "signing app inside-out with DEVELOPER_ID_APPLICATION"
  "$CODESIGN_BIN" "${options[@]}" --sign "$SIGN_IDENTITY" "$framework/Versions/B/Autoupdate"
  "$CODESIGN_BIN" "${options[@]}" --sign "$SIGN_IDENTITY" "$framework/Versions/B/Updater.app"
  "$CODESIGN_BIN" "${options[@]}" --sign "$SIGN_IDENTITY" "$framework/Versions/B/XPCServices/Downloader.xpc"
  "$CODESIGN_BIN" "${options[@]}" --sign "$SIGN_IDENTITY" "$framework/Versions/B/XPCServices/Installer.xpc"
  "$CODESIGN_BIN" "${options[@]}" --sign "$SIGN_IDENTITY" "$framework"
  "$CODESIGN_BIN" "${options[@]}" --sign "$SIGN_IDENTITY" "$RESOURCES_DIR/updatebar"
  "$CODESIGN_BIN" "${options[@]}" --sign "$SIGN_IDENTITY" "$MACOS_DIR/UpdateBar"
  "$CODESIGN_BIN" "${options[@]}" --sign "$SIGN_IDENTITY" "$STAGING_APP_DIR"
}

write_info_plist() {
  local plist="$CONTENTS_DIR/Info.plist"
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>UpdateBar</string>
  <key>CFBundleIconFile</key>
  <string>UpdateBar.icns</string>
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

  "$PLUTIL_BIN" -insert SUFeedURL -string "$UPDATE_FEED_URL" "$plist"
  "$PLUTIL_BIN" -insert SUPublicEDKey -string "$SPARKLE_ED_KEY" "$plist"
  "$PLUTIL_BIN" -insert SUEnableAutomaticChecks -bool false "$plist"
  "$PLUTIL_BIN" -lint "$plist" >/dev/null
}

validate_runtime_linkage() {
  local executable="$MACOS_DIR/UpdateBar"
  local dependencies=""
  local load_commands=""
  dependencies="$("$OTOOL_BIN" -L "$executable")"
  if [[ "$dependencies" != *"@rpath/Sparkle.framework/"* ]]; then
    fail "packaged UpdateBar executable does not reference @rpath/Sparkle.framework"
  fi
  load_commands="$("$OTOOL_BIN" -l "$executable")"
  if ! printf '%s\n' "$load_commands" | grep -Fq "path @executable_path/../Frameworks "; then
    fail "packaged UpdateBar executable is missing @executable_path/../Frameworks LC_RPATH"
  fi
}

cleanup_staging() {
  if [[ -n "${STAGING_APP_DIR:-}" && -e "$STAGING_APP_DIR" ]]; then
    rm -rf "$STAGING_APP_DIR"
  fi
}
trap cleanup_staging EXIT

validate_inputs
"$SWIFT_BIN" package resolve
discover_sparkle_framework

Scripts/generate-version-source.sh
"$SWIFT_BIN" build -c release --product updatebar
"$SWIFT_BIN" build -c release --product updatebar-menubar \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks

cleanup_staging
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp .build/release/updatebar-menubar "$MACOS_DIR/UpdateBar"
cp .build/release/updatebar "$RESOURCES_DIR/updatebar"
cp "$ICON_SOURCE" "$RESOURCES_DIR/UpdateBar.icns"
"$DITTO_BIN" "$SPARKLE_FRAMEWORK_SOURCE" "$FRAMEWORKS_DIR/Sparkle.framework"
chmod 0755 "$MACOS_DIR/UpdateBar" "$RESOURCES_DIR/updatebar"

validate_framework_symlinks
write_info_plist
"$RESOURCES_DIR/updatebar" --version >/dev/null
validate_runtime_linkage

if [[ "$(uname -s)" == "Darwin" ]]; then
  sign_app_if_requested
fi

if [[ "$(uname -s)" == "Darwin" && "${UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE:-0}" != "1" ]]; then
  Scripts/menubar-smoke-test.sh "$STAGING_APP_DIR"
fi

rm -rf "$APP_DIR"
mv "$STAGING_APP_DIR" "$APP_DIR"
trap - EXIT
echo "$APP_DIR"
