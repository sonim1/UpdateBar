#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source version.env

CODESIGN_BIN="${CODESIGN_BIN:-codesign}"
DITTO_BIN="${DITTO_BIN:-ditto}"
HDIUTIL_BIN="${HDIUTIL_BIN:-hdiutil}"
PLUTIL_BIN="${PLUTIL_BIN:-plutil}"
REALPATH_BIN="${REALPATH_BIN:-realpath}"
RUBY_BIN="${RUBY_BIN:-ruby}"
SECURITY_BIN="${SECURITY_BIN:-security}"
SHASUM_BIN="${SHASUM_BIN:-shasum}"
SPCTL_BIN="${SPCTL_BIN:-spctl}"
XCRUN_BIN="${XCRUN_BIN:-xcrun}"

VERSION="${UPDATEBAR_VERSION:?UPDATEBAR_VERSION is required}"
PUBLIC_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARYTOOL_KEYCHAIN_PROFILE:-}"
NOTARY_KEYCHAIN="${NOTARYTOOL_KEYCHAIN:-}"
SYSTEM_NAME="${UPDATEBAR_TEST_SYSTEM:-$(uname -s)}"
ARCHITECTURE="${UPDATEBAR_TEST_ARCH:-$(uname -m)}"
DIST_DIR="$ROOT/dist"
FINAL_DMG="$DIST_DIR/UpdateBar-${VERSION}-macos-arm64.dmg"
FINAL_CHECKSUM="$FINAL_DMG.sha256"

WORK_DIR=""
MOUNT_POINT=""
ATTACHED_DEVICE=""
TEMP_DMG=""
TEMP_CHECKSUM=""

fail() {
  echo "$*" >&2
  exit 1
}

invalid_input() {
  echo "$*" >&2
  exit 64
}

cleanup() {
  local original_status=$?
  local detach_status=0
  trap - EXIT HUP INT TERM
  if [[ -n "$ATTACHED_DEVICE" ]]; then
    set +e
    "$HDIUTIL_BIN" detach "$ATTACHED_DEVICE" >&2
    detach_status=$?
    set -e
    ATTACHED_DEVICE=""
    MOUNT_POINT=""
  fi
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" && ! -L "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
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

require_command() {
  local executable="$1"
  local purpose="$2"
  if ! command -v "$executable" >/dev/null 2>&1; then
    fail "$executable is required to $purpose"
  fi
}

validate_text_input() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    fail "$label is required and must be a single line"
  fi
}

validate_developer_id_identity() {
  if ! "$RUBY_BIN" -e '
    value = ARGV.fetch(0)
    match = value.match(/\ADeveloper ID Application: (.+) \(([A-Z0-9]{10})\)\z/)
    subject = match && match[1]
    safe = value.valid_encoding? && !value.include?(%q{"}) &&
      value.each_codepoint.none? { |codepoint| codepoint < 0x20 || codepoint == 0x7f }
    valid = safe && subject && !subject.empty? && subject == subject.strip
    exit(valid ? 0 : 1)
  ' "$SIGNING_IDENTITY"; then
    invalid_input "DEVELOPER_ID_APPLICATION must be a Developer ID Application identity ending in a 10-character Team ID"
  fi
}

validate_inputs() {
  if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
    fail "UPDATEBAR_VERSION must contain two or three numeric components"
  fi
  if [[ "$SYSTEM_NAME" != "Darwin" ]]; then
    fail "canonical UpdateBar DMGs must be built on Darwin"
  fi
  if [[ "$ARCHITECTURE" != "arm64" ]]; then
    fail "canonical UpdateBar DMGs must be built on arm64, got $ARCHITECTURE"
  fi

  require_command "$RUBY_BIN" "validate release credentials"
  validate_developer_id_identity
  validate_text_input "NOTARYTOOL_KEYCHAIN_PROFILE" "$NOTARY_PROFILE"
  if [[ ! "$NOTARY_PROFILE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    fail "NOTARYTOOL_KEYCHAIN_PROFILE contains unsafe characters"
  fi
  if [[ -n "$NOTARY_KEYCHAIN" ]]; then
    validate_text_input "NOTARYTOOL_KEYCHAIN" "$NOTARY_KEYCHAIN"
    case "$NOTARY_KEYCHAIN" in
      /*) ;;
      *) fail "NOTARYTOOL_KEYCHAIN must be an absolute path" ;;
    esac
  fi

  if ! "$RUBY_BIN" -rbase64 -e '
    value = ARGV.fetch(0)
    begin
      decoded = Base64.strict_decode64(value)
      exit(decoded.bytesize == 32 && Base64.strict_encode64(decoded) == value ? 0 : 1)
    rescue ArgumentError
      exit 1
    end
  ' "$PUBLIC_KEY"; then
    fail "SPARKLE_PUBLIC_ED_KEY must be canonical Base64 encoding of exactly 32 bytes"
  fi

  require_command "$CODESIGN_BIN" "sign and verify the app DMG"
  require_command "$DITTO_BIN" "stage the app bundle"
  require_command "$HDIUTIL_BIN" "create and mount the app DMG"
  require_command "$PLUTIL_BIN" "parse hdiutil output"
  require_command "$REALPATH_BIN" "validate the DMG mount point"
  require_command "$SHASUM_BIN" "checksum the app DMG"
  require_command "$SECURITY_BIN" "verify the Developer ID identity"
  require_command "$SPCTL_BIN" "assess the notarized app DMG"
  require_command "$XCRUN_BIN" "notarize and staple the app DMG"

  if [[ -e "$DIST_DIR" && ( ! -d "$DIST_DIR" || -L "$DIST_DIR" ) ]]; then
    fail "unsafe distribution directory: $DIST_DIR"
  fi
  if [[ -e "$FINAL_DMG" || -L "$FINAL_DMG" || -e "$FINAL_CHECKSUM" || -L "$FINAL_CHECKSUM" ]]; then
    fail "refusing to overwrite existing app DMG output"
  fi
}

preflight_release_credentials() {
  local identity_output=""
  local security_status=0
  local identity_found=0
  local line=""
  local candidate=""
  local security_args=(find-identity -v -p codesigning)
  local history_args=(notarytool history --keychain-profile "$NOTARY_PROFILE")

  if [[ -n "$NOTARY_KEYCHAIN" ]]; then
    security_args+=("$NOTARY_KEYCHAIN")
    history_args+=(--keychain "$NOTARY_KEYCHAIN")
  fi

  if identity_output="$("$SECURITY_BIN" "${security_args[@]}")"; then
    :
  else
    security_status=$?
    echo "unable to query Developer ID signing identities" >&2
    exit "$security_status"
  fi
  while IFS= read -r line; do
    case "$line" in
      *'"'*'"'*)
        candidate="${line#*\"}"
        candidate="${candidate%%\"*}"
        if [[ "$candidate" == "$SIGNING_IDENTITY" ]]; then
          identity_found=1
        fi
        ;;
    esac
  done <<<"$identity_output"
  if [[ "$identity_found" != "1" ]]; then
    fail "DEVELOPER_ID_APPLICATION was not found in the selected keychain"
  fi

  "$XCRUN_BIN" "${history_args[@]}" >/dev/null
}

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

detach_attached_device() {
  [[ -n "$ATTACHED_DEVICE" ]] || return 0
  "$HDIUTIL_BIN" detach "$ATTACHED_DEVICE" >&2
  ATTACHED_DEVICE=""
  MOUNT_POINT=""
}

extract_mount_point() {
  local plist_path="$1"
  local json_path="$2"
  "$PLUTIL_BIN" -convert json -o "$json_path" "$plist_path" || return $?
  "$RUBY_BIN" -rjson -e '
    document = JSON.parse(File.binread(ARGV.fetch(0)))
    entities = document.is_a?(Array) ? document : document.fetch("system-entities", [])
    mount_points = entities.each_with_object([]) do |entity, values|
      values << entity["mount-point"] if entity.is_a?(Hash) && entity.key?("mount-point")
    end
    valid = mount_points.length == 1 && mount_points.first.is_a?(String) &&
      mount_points.first.start_with?("/") && !mount_points.first.include?("\0") &&
      !mount_points.first.include?("\n") && !mount_points.first.include?("\r")
    exit 1 unless valid
    print mount_points.first
  ' "$json_path"
}

publish_outputs() {
  local status=0
  ln "$TEMP_DMG" "$FINAL_DMG" || return $?
  ln "$TEMP_CHECKSUM" "$FINAL_CHECKSUM" || {
    status=$?
    if [[ -f "$FINAL_DMG" && ! -L "$FINAL_DMG" && "$FINAL_DMG" -ef "$TEMP_DMG" ]]; then
      rm -f "$FINAL_DMG"
    fi
    return "$status"
  }
  rm -f "$TEMP_DMG" "$TEMP_CHECKSUM"
}

validate_inputs
preflight_release_credentials
mkdir -p "$DIST_DIR"
WORK_DIR="$(mktemp -d "$DIST_DIR/.updatebar-dmg.XXXXXX")"
if [[ ! -d "$WORK_DIR" || -L "$WORK_DIR" ]]; then
  fail "failed to create a safe DMG work directory"
fi

STAGING_DIR="$WORK_DIR/staging"
ATTACH_PLIST="$WORK_DIR/attach.plist"
ATTACH_JSON="$WORK_DIR/attach.json"
TEMP_DMG="$WORK_DIR/UpdateBar-${VERSION}-macos-arm64.dmg"
TEMP_CHECKSUM="$WORK_DIR/UpdateBar-${VERSION}-macos-arm64.dmg.sha256"

UPDATEBAR_SIGN_APP=1 \
DEVELOPER_ID_APPLICATION="$SIGNING_IDENTITY" \
SPARKLE_PUBLIC_ED_KEY="$PUBLIC_KEY" \
UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 \
  "$ROOT/Scripts/package-app.sh" >&2

APP_DIR="$DIST_DIR/UpdateBar.app"
if [[ ! -d "$APP_DIR" || -L "$APP_DIR" ]]; then
  fail "package-app.sh did not create a safe UpdateBar.app bundle"
fi
"$CODESIGN_BIN" --verify --strict --deep "$APP_DIR" >&2

mkdir "$STAGING_DIR"
"$DITTO_BIN" "$APP_DIR" "$STAGING_DIR/UpdateBar.app" >&2
ln -s /Applications "$STAGING_DIR/Applications"
if [[ "$(readlink "$STAGING_DIR/Applications")" != "/Applications" ]]; then
  fail "failed to create the Applications symlink"
fi

"$HDIUTIL_BIN" create \
  -volname "UpdateBar ${VERSION}" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  "$TEMP_DMG" >&2
if [[ ! -f "$TEMP_DMG" || -L "$TEMP_DMG" ]]; then
  fail "hdiutil did not create a safe regular DMG"
fi

"$CODESIGN_BIN" --force --timestamp --sign "$SIGNING_IDENTITY" "$TEMP_DMG" >&2
"$CODESIGN_BIN" --verify --strict "$TEMP_DMG" >&2

NOTARY_ARGS=(notarytool submit "$TEMP_DMG" --wait --keychain-profile "$NOTARY_PROFILE")
if [[ -n "$NOTARY_KEYCHAIN" ]]; then
  NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
fi
"$XCRUN_BIN" "${NOTARY_ARGS[@]}" >&2
"$XCRUN_BIN" stapler staple "$TEMP_DMG" >&2
"$XCRUN_BIN" stapler validate "$TEMP_DMG" >&2
"$SPCTL_BIN" -a -vv -t open --context context:primary-signature "$TEMP_DMG" >&2

"$HDIUTIL_BIN" attach -plist -nobrowse -readonly "$TEMP_DMG" >"$ATTACH_PLIST"
if ATTACHED_DEVICE="$(extract_attached_device "$ATTACH_PLIST")"; then
  :
else
  device_status=$?
  echo "unable to identify exactly one safe attached DMG device" >&2
  exit "$device_status"
fi
if MOUNT_POINT="$(extract_mount_point "$ATTACH_PLIST" "$ATTACH_JSON")"; then
  :
else
  mount_status=$?
  echo "unable to identify exactly one safe DMG mount point" >&2
  exit "$mount_status"
fi
if [[ "${UPDATEBAR_TEST_ALLOW_NON_VOLUMES_MOUNT:-0}" != "1" && "$MOUNT_POINT" != /Volumes/* ]]; then
  fail "unsafe DMG mount point: $MOUNT_POINT"
fi
MOUNT_REAL="$("$REALPATH_BIN" "$MOUNT_POINT")"
if [[ "${UPDATEBAR_TEST_ALLOW_NON_VOLUMES_MOUNT:-0}" != "1" && "$MOUNT_REAL" != "$MOUNT_POINT" ]]; then
  fail "noncanonical DMG mount point: $MOUNT_POINT"
fi
MOUNTED_APP="$MOUNT_POINT/UpdateBar.app"
if [[ ! -d "$MOUNTED_APP" || -L "$MOUNTED_APP" ]]; then
  fail "mounted DMG does not contain a safe UpdateBar.app"
fi
"$SPCTL_BIN" -a -vv -t execute "$MOUNTED_APP" >&2
detach_attached_device

DMG_SHA="$("$SHASUM_BIN" -a 256 "$TEMP_DMG" | awk '{print $1}')"
if [[ ! "$DMG_SHA" =~ ^[0-9a-f]{64}$ ]]; then
  fail "shasum produced an invalid SHA-256 digest"
fi
printf '%s  %s\n' "$DMG_SHA" "$(basename "$FINAL_DMG")" >"$TEMP_CHECKSUM"
if [[ ! -f "$TEMP_CHECKSUM" || -L "$TEMP_CHECKSUM" ]]; then
  fail "failed to create a safe app DMG checksum"
fi

publish_outputs
trap - EXIT
rm -rf "$WORK_DIR"
WORK_DIR=""
printf '%s\n' "$FINAL_DMG"
