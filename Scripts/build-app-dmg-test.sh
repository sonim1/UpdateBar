#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"

TMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_ROOT="$TMP_DIR/root"
BIN_DIR="$TMP_DIR/bin"
LOG="$TMP_DIR/commands.log"
MOUNT_DIR="$TMP_DIR/mount"
ATTACH_MOUNT_FILE="$TMP_DIR/attach-mount.txt"
LN_COUNT_FILE="$TMP_DIR/ln-count.txt"
VALID_KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
export FAKE_ATTACH_MOUNT_FILE="$ATTACH_MOUNT_FILE"

mkdir -p "$TEST_ROOT/Scripts" "$TEST_ROOT/Assets/AppIcon" "$BIN_DIR" \
  "$MOUNT_DIR/UpdateBar.app/Contents/MacOS" \
  "$MOUNT_DIR/UpdateBar.app/Contents/Resources" \
  "$MOUNT_DIR/UpdateBar.app/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/Scripts/build-app-dmg.sh" "$TEST_ROOT/Scripts/build-app-dmg.sh"
cp "$ROOT/Scripts/app-dmg-smoke-test.sh" "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh"
cp "$ROOT/version.env" "$TEST_ROOT/version.env"
printf 'icon\n' >"$TEST_ROOT/Assets/AppIcon/UpdateBar.icns"
printf 'app\n' >"$MOUNT_DIR/UpdateBar.app/Contents/MacOS/UpdateBar"
chmod +x "$MOUNT_DIR/UpdateBar.app/Contents/MacOS/UpdateBar"
printf 'plist\n' >"$MOUNT_DIR/UpdateBar.app/Contents/Info.plist"
printf 'icon\n' >"$MOUNT_DIR/UpdateBar.app/Contents/Resources/UpdateBar.icns"
cat >"$MOUNT_DIR/UpdateBar.app/Contents/Resources/updatebar" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_CLI_VERSION:-0.5.0}"
SH
chmod +x "$MOUNT_DIR/UpdateBar.app/Contents/Resources/updatebar"
ln -s /Applications "$MOUNT_DIR/Applications"

cat >"$TEST_ROOT/Scripts/package-app.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'package:%s:%s:%s\n' "${UPDATEBAR_SIGN_APP:-}" "${DEVELOPER_ID_APPLICATION:-}" "${SPARKLE_PUBLIC_ED_KEY:-}" >>"${COMMAND_LOG:?}"
printf 'package progress\n'
mkdir -p dist/UpdateBar.app/Contents/MacOS
printf 'app\n' >dist/UpdateBar.app/Contents/MacOS/UpdateBar
SH

cat >"$BIN_DIR/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'codesign:%s\n' "$*" >>"${COMMAND_LOG:?}"
printf 'codesign progress\n'
if [[ "${FAIL_COMMAND:-}" == "codesign" ]]; then exit 23; fi
SH

cat >"$BIN_DIR/ditto" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'ditto:%s\n' "$*" >>"${COMMAND_LOG:?}"
printf 'ditto progress\n'
cp -R "$1" "$2"
SH

cat >"$BIN_DIR/security" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'security:%s\n' "$*" >>"${COMMAND_LOG:?}"
printf 'security progress\n'
if [[ "${FAIL_SECURITY:-0}" == "1" ]]; then exit 41; fi
if [[ "${FAKE_IDENTITY_PRESENT:-1}" == "1" ]]; then
  printf '  1) ABCDEF "%s"\n' "${FAKE_IDENTITY:-Developer ID Application: Example (TEAMID1234)}"
fi
SH

cat >"$BIN_DIR/hdiutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'hdiutil:%s\n' "$*" >>"${COMMAND_LOG:?}"
case "$1" in
  create)
    target="${*: -1}"
    printf 'dmg bytes\n' >"$target"
    printf 'create progress\n'
    ;;
  attach)
    requested_mount=""
    previous=""
    for argument in "$@"; do
      if [[ "$previous" == "-mountpoint" ]]; then requested_mount="$argument"; fi
      previous="$argument"
    done
    [[ -n "$requested_mount" ]] || exit 65
    printf '%s\n' "$requested_mount" >"${FAKE_ATTACH_MOUNT_FILE:?}"
    cp -R "${FAKE_MOUNT_DIR:?}/." "$requested_mount/"
    device_mode="${FAKE_DEVICE_MODE:-valid}"
    device_xml=""
    case "$device_mode" in
      valid) device_xml='<dict><key>dev-entry</key><string>/dev/disk42</string></dict>' ;;
      malformed) device_xml='<dict><key>dev-entry</key><string>/dev/not-a-disk</string></dict>' ;;
      multiple) device_xml='<dict><key>dev-entry</key><string>/dev/disk42</string></dict><dict><key>dev-entry</key><string>/dev/disk43</string></dict>' ;;
      missing) ;;
    esac
    mount_xml=""
    if [[ "${FAKE_MOUNT_MODE:-one}" != "zero" ]]; then
      mount_xml="<dict><key>mount-point</key><string>${requested_mount}</string></dict>"
    fi
    if [[ "${FAKE_MOUNT_MODE:-one}" == "multiple" ]]; then
      mount_xml="$mount_xml<dict><key>mount-point</key><string>${requested_mount}/second</string></dict>"
    fi
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>system-entities</key><array>
$device_xml
$mount_xml
</array></dict></plist>
PLIST
    ;;
  detach)
    printf 'detach progress\n'
    if [[ "${FAIL_DETACH:-0}" == "1" ]]; then exit 47; fi
    ;;
  *) exit 64 ;;
esac
SH

cat >"$BIN_DIR/ln" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [[ -f "${LN_COUNT_FILE:?}" ]]; then count="$(cat "$LN_COUNT_FILE")"; fi
count=$((count + 1))
printf '%s\n' "$count" >"$LN_COUNT_FILE"
printf 'ln:%s:%s\n' "$1" "$2" >>"${COMMAND_LOG:?}"
if [[ "${RACE_ON_LN_CALL:-0}" == "$count" ]]; then
  printf 'racing output\n' >"$2"
  exit 45
fi
if [[ "${FAIL_LN_CALL:-0}" == "$count" ]]; then exit 44; fi
/bin/ln "$1" "$2"
if [[ "${SIGNAL_AFTER_LN_CALL:-0}" == "$count" ]]; then kill -TERM "$PPID"; fi
SH

cat >"$BIN_DIR/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcrun:%s\n' "$*" >>"${COMMAND_LOG:?}"
printf 'xcrun progress\n'
if [[ "${FAIL_COMMAND:-}" == "history" && "${2:-}" == "history" ]]; then exit 31; fi
if [[ "${FAIL_COMMAND:-}" == "notary" && "${2:-}" == "submit" ]]; then exit 29; fi
SH

cat >"$BIN_DIR/spctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'spctl:%s\n' "$*" >>"${COMMAND_LOG:?}"
printf 'spctl progress\n'
SH

cat >"$BIN_DIR/shasum" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'shasum:%s\n' "$*" >>"${COMMAND_LOG:?}"
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  %s\n' "${*: -1}"
SH

cat >"$BIN_DIR/plutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'plutil:%s\n' "$*" >>"${COMMAND_LOG:?}"
if [[ "${FAIL_PLUTIL:-0}" == "1" && "$1" == "-convert" ]]; then exit 37; fi
if [[ "${FAIL_PLUTIL:-0}" == "signal" && "$1" == "-convert" ]]; then
  kill -TERM "$PPID"
  sleep 1
  exit 38
fi
if [[ "$1" == "-extract" ]]; then
  case "$2" in
    CFBundleIdentifier) printf 'com.sonim1.UpdateBar\n' ;;
    CFBundleExecutable) printf '%s\n' "${FAKE_CF_BUNDLE_EXECUTABLE:-UpdateBar}" ;;
    CFBundleIconFile) printf '%s\n' "${FAKE_CF_BUNDLE_ICON_FILE:-UpdateBar.icns}" ;;
    CFBundlePackageType) printf '%s\n' "${FAKE_CF_BUNDLE_PACKAGE_TYPE:-APPL}" ;;
    LSUIElement) printf '%s\n' "${FAKE_LSUI_ELEMENT:-true}" ;;
    CFBundleShortVersionString|CFBundleVersion) printf '%s\n' "${FAKE_VERSION:?}" ;;
    SUFeedURL) printf 'https://updates.updatebar.sonim1.com/appcast.xml\n' ;;
    SUPublicEDKey) printf '%s\n' "${FAKE_PUBLIC_KEY:?}" ;;
    *) exit 1 ;;
  esac
  exit 0
fi
output=""
previous=""
for argument in "$@"; do
  if [[ "$previous" == "-o" ]]; then output="$argument"; fi
  previous="$argument"
done
attached_mount="$(cat "${FAKE_ATTACH_MOUNT_FILE:?}")"
case "${FAKE_MOUNT_MODE:-one}" in
  zero) printf '[{"dev-entry":"/dev/disk42"}]\n' >"$output" ;;
  multiple) printf '[{"mount-point":"%s"},{"mount-point":"%s/second"}]\n' "$attached_mount" "$attached_mount" >"$output" ;;
  *) printf '[{"mount-point":"%s"}]\n' "$attached_mount" >"$output" ;;
esac
SH

chmod +x "$TEST_ROOT/Scripts/package-app.sh" "$BIN_DIR"/*

run_builder() {
  (
    cd "$TEST_ROOT"
    rm -f "$LN_COUNT_FILE" "$ATTACH_MOUNT_FILE"
    env \
      COMMAND_LOG="$LOG" \
      FAKE_MOUNT_DIR="$MOUNT_DIR" \
      FAKE_ATTACH_MOUNT_FILE="$ATTACH_MOUNT_FILE" \
      LN_COUNT_FILE="$LN_COUNT_FILE" \
      FAKE_VERSION="$UPDATEBAR_VERSION" \
      FAKE_PUBLIC_KEY="$VALID_KEY" \
      SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" \
      DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID1234)' \
      NOTARYTOOL_KEYCHAIN_PROFILE=updatebar-notary \
      CODESIGN_BIN="$BIN_DIR/codesign" \
      SECURITY_BIN="$BIN_DIR/security" \
      DITTO_BIN="$BIN_DIR/ditto" \
      HDIUTIL_BIN="$BIN_DIR/hdiutil" \
      LN_BIN="$BIN_DIR/ln" \
      XCRUN_BIN="$BIN_DIR/xcrun" \
      SPCTL_BIN="$BIN_DIR/spctl" \
      SHASUM_BIN="$BIN_DIR/shasum" \
      PLUTIL_BIN="$BIN_DIR/plutil" \
      REALPATH_BIN="$(command -v realpath)" \
      RUBY_BIN="$(command -v ruby)" \
      "$@" \
      bash Scripts/build-app-dmg.sh
  )
}

run_smoke() {
  env \
    COMMAND_LOG="$LOG" FAKE_MOUNT_DIR="$MOUNT_DIR" FAKE_VERSION="$UPDATEBAR_VERSION" \
    FAKE_PUBLIC_KEY="$VALID_KEY" SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" \
    HDIUTIL_BIN="$BIN_DIR/hdiutil" PLUTIL_BIN="$BIN_DIR/plutil" \
    SHASUM_BIN="$BIN_DIR/shasum" RUBY_BIN="$(command -v ruby)" \
    REALPATH_BIN="$(command -v realpath)" "$@" \
    bash "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh" "$expected"
}

assert_absent_outputs() {
  [[ ! -e "$TEST_ROOT/dist/UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg" ]]
  [[ ! -e "$TEST_ROOT/dist/UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg.sha256" ]]
}
expected="$TEST_ROOT/dist/UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg"

# Required metadata must fail before package/build tools run.
: >"$LOG"
set +e
(
  cd "$TEST_ROOT"
  COMMAND_LOG="$LOG" \
    DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID1234)' NOTARYTOOL_KEYCHAIN_PROFILE=profile \
    bash Scripts/build-app-dmg.sh
) >/dev/null 2>&1
missing_key_status=$?
set -e
if [[ "$missing_key_status" -eq 0 || -s "$LOG" ]]; then
  echo "missing Sparkle key must fail before external build commands" >&2
  exit 1
fi
assert_absent_outputs

# Every other required release input is also validated before mutation.
for missing_case in identity profile invalid-key; do
  : >"$LOG"
  set +e
  (
    cd "$TEST_ROOT"
    case "$missing_case" in
      identity)
        COMMAND_LOG="$LOG" \
          SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" NOTARYTOOL_KEYCHAIN_PROFILE=profile \
          bash Scripts/build-app-dmg.sh
        ;;
      profile)
        COMMAND_LOG="$LOG" \
          SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID1234)' \
          bash Scripts/build-app-dmg.sh
        ;;
      invalid-key)
        COMMAND_LOG="$LOG" \
          SPARKLE_PUBLIC_ED_KEY='not-base64' DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID1234)' \
          NOTARYTOOL_KEYCHAIN_PROFILE=profile bash Scripts/build-app-dmg.sh
        ;;
    esac
  ) >/dev/null 2>&1
  required_status=$?
  set -e
  if [[ "$required_status" -eq 0 || -s "$LOG" ]]; then
    echo "$missing_case must fail before external build commands" >&2
    exit 1
  fi
  assert_absent_outputs
done

# Hostile test-looking environment values must not override production uname.
: >"$LOG"
set +e
hostile_platform_output="$(run_builder UPDATEBAR_TEST_SYSTEM=Linux UPDATEBAR_TEST_ARCH=x86_64 2>/dev/null)"
hostile_platform_status=$?
set -e
if [[ "$hostile_platform_status" -ne 0 || "$hostile_platform_output" != *"UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg" ]]; then
  echo "UPDATEBAR_TEST_* values affected production platform detection" >&2
  exit 1
fi
rm -f "$TEST_ROOT/dist/UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg" \
  "$TEST_ROOT/dist/UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg.sha256"
assert_absent_outputs

# Signing identity and notary credentials are proven usable before packaging.
for preflight_case in missing-identity security-failure history-failure; do
  : >"$LOG"
  set +e
  case "$preflight_case" in
    missing-identity) run_builder FAKE_IDENTITY_PRESENT=0 >/dev/null 2>&1 ;;
    security-failure) run_builder FAIL_SECURITY=1 >/dev/null 2>&1 ;;
    history-failure) run_builder FAIL_COMMAND=history >/dev/null 2>&1 ;;
  esac
  preflight_status=$?
  set -e
  case "$preflight_case:$preflight_status" in
    missing-identity:1|security-failure:41|history-failure:31) ;;
    *) echo "unexpected $preflight_case status: $preflight_status" >&2; exit 1 ;;
  esac
  if grep -Eq '^package:|^codesign:|^hdiutil:' "$LOG"; then
    echo "$preflight_case reached external build commands" >&2
    exit 1
  fi
  assert_absent_outputs
done

# Installed identities of the wrong certificate type are invalid input and
# must be rejected before even querying the keychain.
for wrong_identity in \
  'Apple Development: Example (TEAMID1234)' \
  'Apple Distribution: Example (TEAMID1234)' \
  '-' \
  '0123456789ABCDEF' \
  'prefix Developer ID Application: Example (TEAMID1234)' \
  'Developer ID Application: Example (SHORT)' \
  'Developer ID Application: (TEAMID1234)' \
  'Developer ID Application: Example (TEAMID1234) suffix' \
  $'Developer ID Application: Example\tName (TEAMID1234)' \
  $'Developer ID Application: Example (TEAMID1234)\nApple Development: Other (TEAMID1234)'; do
  : >"$LOG"
  set +e
  run_builder DEVELOPER_ID_APPLICATION="$wrong_identity" FAKE_IDENTITY="$wrong_identity" \
    >"$TMP_DIR/wrong-identity.stdout" 2>"$TMP_DIR/wrong-identity.stderr"
  wrong_identity_status=$?
  set -e
  if [[ "$wrong_identity_status" -ne 64 || -s "$TMP_DIR/wrong-identity.stdout" ]]; then
    echo "invalid Developer ID identity form was not rejected with exit 64: $wrong_identity" >&2
    exit 1
  fi
  if grep -Eq '^security:|^xcrun:|^package:' "$LOG"; then
    echo "invalid Developer ID identity reached security/notary/package: $wrong_identity" >&2
    exit 1
  fi
  assert_absent_outputs
done

# Missing, malformed, or ambiguous dev-entry data falls back only to the
# invocation-private mountpoint and can still complete safely.
for device_mode in missing malformed multiple; do
  : >"$LOG"
  device_output="$(run_builder FAKE_DEVICE_MODE="$device_mode" 2>"$TMP_DIR/device-$device_mode.stderr")"
  private_mount="$(cat "$ATTACH_MOUNT_FILE")"
  if [[ "$device_output" != "$expected" ]] \
    || ! grep -Fxq "hdiutil:detach $private_mount" "$LOG" \
    || grep -Eq '^hdiutil:detach /Volumes|^hdiutil:detach /$' "$LOG"; then
    echo "$device_mode dev-entry did not use the exact private mount fallback" >&2
    exit 1
  fi
  rm -f "$expected" "$expected.sha256"
done

# The full notarized DMG flow publishes only the canonical DMG and checksum.
: >"$LOG"
output="$(run_builder NOTARYTOOL_KEYCHAIN=/tmp/test.keychain 2>"$TMP_DIR/builder-success.err")"
if [[ "$output" != "$expected" || "$output" == *$'\n'* || ! -f "$expected" || -L "$expected" ]]; then
  echo "builder did not publish the canonical regular DMG" >&2
  exit 1
fi
if [[ ! -f "$expected.sha256" || -L "$expected.sha256" ]]; then
  echo "builder did not publish the canonical checksum" >&2
  exit 1
fi
if [[ "$(find "$TEST_ROOT/dist" -maxdepth 1 -type f -print | sort)" != "$expected"$'\n'"$expected.sha256" ]]; then
  echo "builder published unexpected app release files" >&2
  find "$TEST_ROOT/dist" -maxdepth 1 -type f -print >&2
  exit 1
fi

package_line="$(grep -n '^package:1:Developer ID Application: Example (TEAMID1234):' "$LOG" | cut -d: -f1)"
security_line="$(grep -n '^security:find-identity -v -p codesigning /tmp/test.keychain$' "$LOG" | cut -d: -f1)"
history_line="$(grep -n '^xcrun:notarytool history --keychain-profile updatebar-notary --keychain /tmp/test.keychain$' "$LOG" | cut -d: -f1)"
app_verify_line="$(grep -n 'codesign:--verify --strict --deep .*dist/UpdateBar.app' "$LOG" | cut -d: -f1)"
create_line="$(grep -n '^hdiutil:create ' "$LOG" | cut -d: -f1)"
dmg_sign_line="$(grep -n 'codesign:.*--sign Developer ID Application: Example (TEAMID1234).*\.dmg' "$LOG" | cut -d: -f1)"
notary_line="$(grep -n 'xcrun:notarytool submit .* --wait --keychain-profile updatebar-notary --keychain /tmp/test.keychain' "$LOG" | cut -d: -f1)"
staple_line="$(grep -n '^xcrun:stapler staple ' "$LOG" | cut -d: -f1)"
validate_line="$(grep -n '^xcrun:stapler validate ' "$LOG" | cut -d: -f1)"
dmg_assess_line="$(grep -n 'spctl:-a -vv -t open --context context:primary-signature ' "$LOG" | cut -d: -f1)"
app_assess_line="$(grep -n 'spctl:-a -vv -t execute .*UpdateBar.app' "$LOG" | cut -d: -f1)"
hash_line="$(grep -n '^shasum:-a 256 ' "$LOG" | cut -d: -f1)"
checksum_link_line="$(grep -n "^ln:.*\.dmg\.sha256:$expected\.sha256$" "$LOG" | cut -d: -f1)"
dmg_link_line="$(grep -n "^ln:.*\.dmg:$expected$" "$LOG" | cut -d: -f1)"
for line in "$security_line" "$history_line" "$package_line" "$app_verify_line" "$create_line" "$dmg_sign_line" "$notary_line" "$staple_line" "$validate_line" "$dmg_assess_line" "$app_assess_line" "$hash_line" "$checksum_link_line" "$dmg_link_line"; do
  [[ "$line" =~ ^[0-9]+$ ]] || { echo "missing required DMG build step" >&2; cat "$LOG" >&2; exit 1; }
done
if ! [[ "$security_line" -lt "$history_line" && "$history_line" -lt "$package_line" && \
  "$package_line" -lt "$app_verify_line" && "$app_verify_line" -lt "$create_line" && \
  "$create_line" -lt "$dmg_sign_line" && "$dmg_sign_line" -lt "$notary_line" && \
  "$notary_line" -lt "$staple_line" && "$staple_line" -lt "$validate_line" && \
  "$validate_line" -lt "$dmg_assess_line" && "$dmg_assess_line" -lt "$app_assess_line" && \
  "$app_assess_line" -lt "$hash_line" && "$hash_line" -lt "$checksum_link_line" && \
  "$checksum_link_line" -lt "$dmg_link_line" ]]; then
  echo "DMG build operations ran out of order" >&2
  cat "$LOG" >&2
  exit 1
fi

# The standalone smoke check mounts read-only and validates app/update metadata.
: >"$LOG"
env \
  COMMAND_LOG="$LOG" \
  FAKE_MOUNT_DIR="$MOUNT_DIR" \
  FAKE_VERSION="$UPDATEBAR_VERSION" \
  FAKE_PUBLIC_KEY="$VALID_KEY" \
  SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" \
  HDIUTIL_BIN="$BIN_DIR/hdiutil" \
  PLUTIL_BIN="$BIN_DIR/plutil" \
  SHASUM_BIN="$BIN_DIR/shasum" \
  RUBY_BIN="$(command -v ruby)" \
  REALPATH_BIN="$(command -v realpath)" \
  bash "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh" "$expected" >/dev/null
if ! grep -Eq "hdiutil:attach -mountpoint .+ -plist -nobrowse -readonly $expected" "$LOG" \
  || ! grep -Fq "hdiutil:detach /dev/disk42" "$LOG"; then
  echo "app DMG smoke did not mount read-only and detach" >&2
  exit 1
fi

for smoke_device_mode in missing malformed multiple; do
  : >"$LOG"
  env \
    COMMAND_LOG="$LOG" FAKE_MOUNT_DIR="$MOUNT_DIR" FAKE_VERSION="$UPDATEBAR_VERSION" \
    FAKE_PUBLIC_KEY="$VALID_KEY" FAKE_DEVICE_MODE="$smoke_device_mode" \
    SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" HDIUTIL_BIN="$BIN_DIR/hdiutil" \
    PLUTIL_BIN="$BIN_DIR/plutil" SHASUM_BIN="$BIN_DIR/shasum" \
    RUBY_BIN="$(command -v ruby)" REALPATH_BIN="$(command -v realpath)" \
    bash "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh" "$expected" \
    >"$TMP_DIR/smoke-device-$smoke_device_mode.stdout" 2>"$TMP_DIR/smoke-device-$smoke_device_mode.stderr"
  fallback_mount="$(cat "$ATTACH_MOUNT_FILE")"
  if ! grep -Fxq "hdiutil:detach $fallback_mount" "$LOG"; then
    echo "smoke $smoke_device_mode dev-entry did not detach its private mount" >&2
    exit 1
  fi
done

# Restored distribution assertions fail behaviorally for missing app payloads,
# wrong bundled CLI versions, and wrong bundle metadata.
CLI_FIXTURE="$MOUNT_DIR/UpdateBar.app/Contents/Resources/updatebar"
ICON_FIXTURE="$MOUNT_DIR/UpdateBar.app/Contents/Resources/UpdateBar.icns"
for smoke_contract in missing-cli wrong-cli-version missing-icon executable icon package-type lsui; do
  : >"$LOG"
  smoke_env=""
  case "$smoke_contract" in
    missing-cli) mv "$CLI_FIXTURE" "$CLI_FIXTURE.saved" ;;
    wrong-cli-version) smoke_env=FAKE_CLI_VERSION=9.9.9 ;;
    missing-icon) mv "$ICON_FIXTURE" "$ICON_FIXTURE.saved" ;;
    executable) smoke_env=FAKE_CF_BUNDLE_EXECUTABLE=Wrong ;;
    icon) smoke_env=FAKE_CF_BUNDLE_ICON_FILE=Wrong.icns ;;
    package-type) smoke_env=FAKE_CF_BUNDLE_PACKAGE_TYPE=FAIL ;;
    lsui) smoke_env=FAKE_LSUI_ELEMENT=false ;;
  esac
  set +e
  if [[ -n "$smoke_env" ]]; then
    run_smoke "$smoke_env" >"$TMP_DIR/contract-$smoke_contract.stdout" 2>"$TMP_DIR/contract-$smoke_contract.stderr"
  else
    run_smoke >"$TMP_DIR/contract-$smoke_contract.stdout" 2>"$TMP_DIR/contract-$smoke_contract.stderr"
  fi
  smoke_contract_status=$?
  set -e
  case "$smoke_contract" in
    missing-cli) mv "$CLI_FIXTURE.saved" "$CLI_FIXTURE" ;;
    missing-icon) mv "$ICON_FIXTURE.saved" "$ICON_FIXTURE" ;;
  esac
  if [[ "$smoke_contract_status" -eq 0 ]]; then
    echo "app DMG smoke accepted invalid $smoke_contract payload" >&2
    exit 1
  fi
done

# Unsafe Applications links are rejected and still detached.
rm "$MOUNT_DIR/Applications"
ln -s ../Applications "$MOUNT_DIR/Applications"
: >"$LOG"
set +e
env \
  COMMAND_LOG="$LOG" FAKE_MOUNT_DIR="$MOUNT_DIR" FAKE_VERSION="$UPDATEBAR_VERSION" \
  FAKE_PUBLIC_KEY="$VALID_KEY" \
  SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" HDIUTIL_BIN="$BIN_DIR/hdiutil" \
  PLUTIL_BIN="$BIN_DIR/plutil" SHASUM_BIN="$BIN_DIR/shasum" \
  RUBY_BIN="$(command -v ruby)" REALPATH_BIN="$(command -v realpath)" \
  bash "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh" "$expected" >/dev/null 2>&1
unsafe_link_status=$?
set -e
if [[ "$unsafe_link_status" -eq 0 || "$(grep -c 'hdiutil:detach /dev/disk42' "$LOG")" -ne 1 ]]; then
  echo "app DMG smoke must reject an unsafe Applications link and detach" >&2
  exit 1
fi
rm "$MOUNT_DIR/Applications"
ln -s /Applications "$MOUNT_DIR/Applications"

# Once attach succeeds, every parse/shape failure detaches the exact device.
for smoke_failure in zero-mount multiple-mount parser-failure missing-device-parser parser-and-detach-failure signal; do
  : >"$LOG"
  smoke_stdout="$TMP_DIR/smoke-$smoke_failure.stdout"
  smoke_stderr="$TMP_DIR/smoke-$smoke_failure.stderr"
  smoke_mode=one
  smoke_plutil=0
  smoke_detach=0
  smoke_device=valid
  expected_status=1
  case "$smoke_failure" in
    zero-mount) smoke_mode=zero ;;
    multiple-mount) smoke_mode=multiple ;;
    parser-failure) smoke_plutil=1; expected_status=37 ;;
    missing-device-parser) smoke_plutil=1; smoke_device=missing; expected_status=37 ;;
    parser-and-detach-failure) smoke_plutil=1; smoke_detach=1; expected_status=37 ;;
    signal) smoke_plutil=signal; expected_status=143 ;;
  esac
  set +e
  env \
    COMMAND_LOG="$LOG" FAKE_MOUNT_DIR="$MOUNT_DIR" FAKE_VERSION="$UPDATEBAR_VERSION" \
    FAKE_PUBLIC_KEY="$VALID_KEY" FAKE_MOUNT_MODE="$smoke_mode" FAIL_PLUTIL="$smoke_plutil" \
    FAKE_DEVICE_MODE="$smoke_device" FAIL_DETACH="$smoke_detach" \
    SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" \
    HDIUTIL_BIN="$BIN_DIR/hdiutil" PLUTIL_BIN="$BIN_DIR/plutil" \
    SHASUM_BIN="$BIN_DIR/shasum" RUBY_BIN="$(command -v ruby)" \
    REALPATH_BIN="$(command -v realpath)" \
    bash "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh" "$expected" \
    >"$smoke_stdout" 2>"$smoke_stderr"
  smoke_status=$?
  set -e
  if [[ "$smoke_status" -ne "$expected_status" || -s "$smoke_stdout" ]]; then
    echo "unexpected $smoke_failure smoke result: status $smoke_status" >&2
    cat "$smoke_stdout" "$smoke_stderr" >&2
    exit 1
  fi
  if [[ "$smoke_device" == "valid" ]]; then
    expected_detach=/dev/disk42
  else
    expected_detach="$(cat "$ATTACH_MOUNT_FILE")"
  fi
  grep -Fxq "hdiutil:detach $expected_detach" "$LOG" || {
    echo "$smoke_failure did not detach the exact safe target" >&2
    cat "$LOG" >&2
    exit 1
  }
done

# A detach failure is the primary failure after otherwise successful smoke.
: >"$LOG"
detach_stdout="$TMP_DIR/detach-failure.stdout"
set +e
env \
  COMMAND_LOG="$LOG" FAKE_MOUNT_DIR="$MOUNT_DIR" FAKE_VERSION="$UPDATEBAR_VERSION" \
  FAKE_PUBLIC_KEY="$VALID_KEY" FAIL_DETACH=1 \
  SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" HDIUTIL_BIN="$BIN_DIR/hdiutil" \
  PLUTIL_BIN="$BIN_DIR/plutil" SHASUM_BIN="$BIN_DIR/shasum" \
  RUBY_BIN="$(command -v ruby)" REALPATH_BIN="$(command -v realpath)" \
  bash "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh" "$expected" \
  >"$detach_stdout" 2>"$TMP_DIR/detach-failure.stderr"
detach_status=$?
set -e
if [[ "$detach_status" -ne 47 || -s "$detach_stdout" ]]; then
  echo "primary detach failure status was not preserved: $detach_status" >&2
  exit 1
fi
if grep '^hdiutil:detach ' "$LOG" | grep -Fvx 'hdiutil:detach /dev/disk42' >/dev/null; then
  echo "detach failure attempted a broad or unrelated detach" >&2
  exit 1
fi

# A symlink posing as the canonical DMG is rejected before mounting.
SYMLINK_DIR="$TMP_DIR/symlink-dmg"
mkdir "$SYMLINK_DIR"
ln -s "$expected" "$SYMLINK_DIR/$(basename "$expected")"
cp "$expected.sha256" "$SYMLINK_DIR/$(basename "$expected").sha256"
: >"$LOG"
set +e
env COMMAND_LOG="$LOG" SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" \
  HDIUTIL_BIN="$BIN_DIR/hdiutil" PLUTIL_BIN="$BIN_DIR/plutil" \
  SHASUM_BIN="$BIN_DIR/shasum" RUBY_BIN="$(command -v ruby)" \
  REALPATH_BIN="$(command -v realpath)" \
  bash "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh" \
  "$SYMLINK_DIR/$(basename "$expected")" >/dev/null 2>&1
symlink_dmg_status=$?
set -e
if [[ "$symlink_dmg_status" -eq 0 || -s "$LOG" ]]; then
  echo "app DMG smoke must reject symlink inputs before mounting" >&2
  exit 1
fi

# Existing outputs fail closed without modification.
original_dmg="$(cat "$expected")"
original_sha="$(cat "$expected.sha256")"
: >"$LOG"
set +e
run_builder >/dev/null 2>&1
existing_status=$?
set -e
if [[ "$existing_status" -eq 0 || "$(cat "$expected")" != "$original_dmg" || "$(cat "$expected.sha256")" != "$original_sha" ]] \
  || grep -Eq '^package:|^codesign:|^hdiutil:' "$LOG"; then
  echo "existing release outputs must fail closed before external commands" >&2
  exit 1
fi

# An Apple validation failure preserves its exact status and publishes nothing.
rm -f "$expected" "$expected.sha256"
: >"$LOG"
set +e
run_builder FAIL_COMMAND=notary >/dev/null 2>&1
notary_status=$?
set -e
if [[ "$notary_status" -ne 29 ]]; then
  echo "notary failure status was not preserved: $notary_status" >&2
  exit 1
fi
assert_absent_outputs
if grep -Eq '^xcrun:stapler|^spctl:|^shasum:' "$LOG"; then
  echo "builder continued after notary failure" >&2
  exit 1
fi

# One-sided preexisting outputs fail closed before package/build and are kept.
for one_sided in dmg checksum; do
  : >"$LOG"
  if [[ "$one_sided" == "dmg" ]]; then
    printf 'preexisting dmg\n' >"$expected"
    one_sided_path="$expected"
  else
    printf 'preexisting checksum\n' >"$expected.sha256"
    one_sided_path="$expected.sha256"
  fi
  original_one_sided="$(cat "$one_sided_path")"
  set +e
  run_builder >"$TMP_DIR/one-sided-$one_sided.stdout" 2>"$TMP_DIR/one-sided-$one_sided.stderr"
  one_sided_status=$?
  set -e
  if [[ "$one_sided_status" -eq 0 || "$(cat "$one_sided_path")" != "$original_one_sided" ]] \
    || grep -Eq '^package:|^codesign:|^hdiutil:' "$LOG"; then
    echo "one-sided $one_sided output was not preserved fail-closed" >&2
    exit 1
  fi
  rm -f "$one_sided_path"
done

# Failure or signal after publishing the checksum removes only this
# transaction's checksum and leaves the DMG commit marker absent.
for publish_failure in signal second-link; do
  : >"$LOG"
  set +e
  if [[ "$publish_failure" == "signal" ]]; then
    run_builder SIGNAL_AFTER_LN_CALL=1 >"$TMP_DIR/publish-$publish_failure.stdout" 2>"$TMP_DIR/publish-$publish_failure.stderr"
    publish_status=$?
    expected_publish_status=143
  else
    run_builder FAIL_LN_CALL=2 >"$TMP_DIR/publish-$publish_failure.stdout" 2>"$TMP_DIR/publish-$publish_failure.stderr"
    publish_status=$?
    expected_publish_status=44
  fi
  set -e
  if [[ "$publish_status" -ne "$expected_publish_status" || -s "$TMP_DIR/publish-$publish_failure.stdout" ]]; then
    echo "unexpected $publish_failure transaction status: $publish_status" >&2
    exit 1
  fi
  assert_absent_outputs
done

# A non-cooperating racer creating the DMG path is preserved, while this
# transaction's checksum is rolled back.
: >"$LOG"
set +e
run_builder RACE_ON_LN_CALL=2 >"$TMP_DIR/publish-race.stdout" 2>"$TMP_DIR/publish-race.stderr"
race_status=$?
set -e
if [[ "$race_status" -ne 45 || ! -f "$expected" || "$(cat "$expected")" != "racing output" \
  || -e "$expected.sha256" ]]; then
  echo "racing DMG output was deleted or a partial checksum remained" >&2
  exit 1
fi
rm -f "$expected"

# Builder-side post-attach parse failures also detach by device and never emit
# a final path or publish partial outputs.
for builder_failure in zero-mount multiple-mount parser-failure; do
  : >"$LOG"
  builder_stdout="$TMP_DIR/builder-$builder_failure.stdout"
  builder_mode=one
  builder_plutil=0
  expected_status=1
  case "$builder_failure" in
    zero-mount) builder_mode=zero ;;
    multiple-mount) builder_mode=multiple ;;
    parser-failure) builder_plutil=1; expected_status=37 ;;
  esac
  set +e
  run_builder FAKE_MOUNT_MODE="$builder_mode" FAIL_PLUTIL="$builder_plutil" \
    >"$builder_stdout" 2>"$TMP_DIR/builder-$builder_failure.stderr"
  builder_status=$?
  set -e
  if [[ "$builder_status" -ne "$expected_status" || -s "$builder_stdout" ]]; then
    echo "unexpected builder $builder_failure result: status $builder_status" >&2
    exit 1
  fi
  assert_absent_outputs
  if [[ "$(grep -c '^hdiutil:detach /dev/disk42$' "$LOG")" -ne 1 ]]; then
    echo "builder $builder_failure did not detach exactly the attached device" >&2
    cat "$LOG" >&2
    exit 1
  fi
done

# Builder layout validation failures detach the device and keep stdout empty.
mv "$MOUNT_DIR/UpdateBar.app" "$MOUNT_DIR/UpdateBar.app.saved"
: >"$LOG"
set +e
run_builder >"$TMP_DIR/builder-layout.stdout" 2>"$TMP_DIR/builder-layout.stderr"
builder_layout_status=$?
set -e
mv "$MOUNT_DIR/UpdateBar.app.saved" "$MOUNT_DIR/UpdateBar.app"
if [[ "$builder_layout_status" -eq 0 || -s "$TMP_DIR/builder-layout.stdout" ]]; then
  echo "builder accepted a mounted DMG without UpdateBar.app" >&2
  exit 1
fi
assert_absent_outputs
if [[ "$(grep -c '^hdiutil:detach /dev/disk42$' "$LOG")" -ne 1 ]]; then
  echo "builder layout failure did not detach exactly the attached device" >&2
  exit 1
fi

# Builder detach failures are surfaced as the primary failure and never publish.
: >"$LOG"
set +e
run_builder FAIL_DETACH=1 >"$TMP_DIR/builder-detach.stdout" 2>"$TMP_DIR/builder-detach.stderr"
builder_detach_status=$?
set -e
if [[ "$builder_detach_status" -ne 47 || -s "$TMP_DIR/builder-detach.stdout" ]]; then
  echo "builder detach failure status was not preserved: $builder_detach_status" >&2
  exit 1
fi
assert_absent_outputs
if grep '^hdiutil:detach ' "$LOG" | grep -Fvx 'hdiutil:detach /dev/disk42' >/dev/null; then
  echo "builder detach failure attempted a broad or unrelated detach" >&2
  exit 1
fi

echo "build app DMG behavior ok"
