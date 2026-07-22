#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_ROOT="$TMP_DIR/root"
BIN_DIR="$TMP_DIR/bin"
LOG="$TMP_DIR/commands.log"
MOUNT_DIR="$TMP_DIR/mount"
VALID_KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

mkdir -p "$TEST_ROOT/Scripts" "$TEST_ROOT/Assets/AppIcon" "$BIN_DIR" \
  "$MOUNT_DIR/UpdateBar.app/Contents/MacOS" \
  "$MOUNT_DIR/UpdateBar.app/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/Scripts/build-app-dmg.sh" "$TEST_ROOT/Scripts/build-app-dmg.sh"
cp "$ROOT/Scripts/app-dmg-smoke-test.sh" "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh"
cp "$ROOT/version.env" "$TEST_ROOT/version.env"
printf 'icon\n' >"$TEST_ROOT/Assets/AppIcon/UpdateBar.icns"
printf 'app\n' >"$MOUNT_DIR/UpdateBar.app/Contents/MacOS/UpdateBar"
chmod +x "$MOUNT_DIR/UpdateBar.app/Contents/MacOS/UpdateBar"
printf 'plist\n' >"$MOUNT_DIR/UpdateBar.app/Contents/Info.plist"
ln -s /Applications "$MOUNT_DIR/Applications"

cat >"$TEST_ROOT/Scripts/package-app.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'package:%s:%s:%s\n' "${UPDATEBAR_SIGN_APP:-}" "${DEVELOPER_ID_APPLICATION:-}" "${SPARKLE_PUBLIC_ED_KEY:-}" >>"${COMMAND_LOG:?}"
mkdir -p dist/UpdateBar.app/Contents/MacOS
printf 'app\n' >dist/UpdateBar.app/Contents/MacOS/UpdateBar
SH

cat >"$BIN_DIR/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'codesign:%s\n' "$*" >>"${COMMAND_LOG:?}"
if [[ "${FAIL_COMMAND:-}" == "codesign" ]]; then exit 23; fi
SH

cat >"$BIN_DIR/ditto" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'ditto:%s\n' "$*" >>"${COMMAND_LOG:?}"
cp -R "$1" "$2"
SH

cat >"$BIN_DIR/hdiutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'hdiutil:%s\n' "$*" >>"${COMMAND_LOG:?}"
case "$1" in
  create)
    target="${*: -1}"
    printf 'dmg bytes\n' >"$target"
    ;;
  attach)
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><array><dict><key>mount-point</key><string>${FAKE_MOUNT_DIR:?}</string></dict></array></plist>
PLIST
    ;;
  detach) ;;
  *) exit 64 ;;
esac
SH

cat >"$BIN_DIR/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcrun:%s\n' "$*" >>"${COMMAND_LOG:?}"
if [[ "${FAIL_COMMAND:-}" == "notary" && "$1" == "notarytool" ]]; then exit 29; fi
SH

cat >"$BIN_DIR/spctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'spctl:%s\n' "$*" >>"${COMMAND_LOG:?}"
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
if [[ "$1" == "-extract" ]]; then
  case "$2" in
    CFBundleIdentifier) printf 'com.sonim1.UpdateBar\n' ;;
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
printf '[{"mount-point":"%s"}]\n' "${FAKE_MOUNT_DIR:?}" >"$output"
SH

chmod +x "$TEST_ROOT/Scripts/package-app.sh" "$BIN_DIR"/*

run_builder() {
  (
    cd "$TEST_ROOT"
    env \
      COMMAND_LOG="$LOG" \
      FAKE_MOUNT_DIR="$MOUNT_DIR" \
      FAKE_VERSION="$UPDATEBAR_VERSION" \
      FAKE_PUBLIC_KEY="$VALID_KEY" \
      UPDATEBAR_TEST_SYSTEM=Darwin \
      UPDATEBAR_TEST_ARCH=arm64 \
      UPDATEBAR_TEST_ALLOW_NON_VOLUMES_MOUNT=1 \
      SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" \
      DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)' \
      NOTARYTOOL_KEYCHAIN_PROFILE=updatebar-notary \
      CODESIGN_BIN="$BIN_DIR/codesign" \
      DITTO_BIN="$BIN_DIR/ditto" \
      HDIUTIL_BIN="$BIN_DIR/hdiutil" \
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

assert_absent_outputs() {
  [[ ! -e "$TEST_ROOT/dist/UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg" ]]
  [[ ! -e "$TEST_ROOT/dist/UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg.sha256" ]]
}

# Required metadata must fail before package/build tools run.
: >"$LOG"
set +e
(
  cd "$TEST_ROOT"
  COMMAND_LOG="$LOG" UPDATEBAR_TEST_SYSTEM=Darwin UPDATEBAR_TEST_ARCH=arm64 \
    DEVELOPER_ID_APPLICATION=identity NOTARYTOOL_KEYCHAIN_PROFILE=profile \
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
        COMMAND_LOG="$LOG" UPDATEBAR_TEST_SYSTEM=Darwin UPDATEBAR_TEST_ARCH=arm64 \
          SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" NOTARYTOOL_KEYCHAIN_PROFILE=profile \
          bash Scripts/build-app-dmg.sh
        ;;
      profile)
        COMMAND_LOG="$LOG" UPDATEBAR_TEST_SYSTEM=Darwin UPDATEBAR_TEST_ARCH=arm64 \
          SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" DEVELOPER_ID_APPLICATION=identity \
          bash Scripts/build-app-dmg.sh
        ;;
      invalid-key)
        COMMAND_LOG="$LOG" UPDATEBAR_TEST_SYSTEM=Darwin UPDATEBAR_TEST_ARCH=arm64 \
          SPARKLE_PUBLIC_ED_KEY='not-base64' DEVELOPER_ID_APPLICATION=identity \
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

# A non-arm64 build must never receive an arm64 artifact name.
: >"$LOG"
set +e
run_builder UPDATEBAR_TEST_ARCH=x86_64 >/dev/null 2>&1
wrong_arch_status=$?
set -e
if [[ "$wrong_arch_status" -eq 0 || -s "$LOG" ]]; then
  echo "non-arm64 build must fail before external build commands" >&2
  exit 1
fi
assert_absent_outputs

# The full notarized DMG flow publishes only the canonical DMG and checksum.
: >"$LOG"
output="$(run_builder NOTARYTOOL_KEYCHAIN=/tmp/test.keychain)"
expected="$TEST_ROOT/dist/UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.dmg"
if [[ "$output" != "$expected" || ! -f "$expected" || -L "$expected" ]]; then
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

package_line="$(grep -n '^package:1:Developer ID Application: Example (TEAMID):' "$LOG" | cut -d: -f1)"
app_verify_line="$(grep -n 'codesign:--verify --strict --deep .*dist/UpdateBar.app' "$LOG" | cut -d: -f1)"
create_line="$(grep -n '^hdiutil:create ' "$LOG" | cut -d: -f1)"
dmg_sign_line="$(grep -n 'codesign:.*--sign Developer ID Application: Example (TEAMID).*\.dmg' "$LOG" | cut -d: -f1)"
notary_line="$(grep -n 'xcrun:notarytool submit .* --wait --keychain-profile updatebar-notary --keychain /tmp/test.keychain' "$LOG" | cut -d: -f1)"
staple_line="$(grep -n '^xcrun:stapler staple ' "$LOG" | cut -d: -f1)"
validate_line="$(grep -n '^xcrun:stapler validate ' "$LOG" | cut -d: -f1)"
dmg_assess_line="$(grep -n 'spctl:-a -vv -t open --context context:primary-signature ' "$LOG" | cut -d: -f1)"
app_assess_line="$(grep -n 'spctl:-a -vv -t execute .*UpdateBar.app' "$LOG" | cut -d: -f1)"
hash_line="$(grep -n '^shasum:-a 256 ' "$LOG" | cut -d: -f1)"
for line in "$package_line" "$app_verify_line" "$create_line" "$dmg_sign_line" "$notary_line" "$staple_line" "$validate_line" "$dmg_assess_line" "$app_assess_line" "$hash_line"; do
  [[ "$line" =~ ^[0-9]+$ ]] || { echo "missing required DMG build step" >&2; cat "$LOG" >&2; exit 1; }
done
if ! [[ "$package_line" -lt "$app_verify_line" && "$app_verify_line" -lt "$create_line" && \
  "$create_line" -lt "$dmg_sign_line" && "$dmg_sign_line" -lt "$notary_line" && \
  "$notary_line" -lt "$staple_line" && "$staple_line" -lt "$validate_line" && \
  "$validate_line" -lt "$dmg_assess_line" && "$dmg_assess_line" -lt "$app_assess_line" && \
  "$app_assess_line" -lt "$hash_line" ]]; then
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
  UPDATEBAR_TEST_ALLOW_NON_VOLUMES_MOUNT=1 \
  SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" \
  HDIUTIL_BIN="$BIN_DIR/hdiutil" \
  PLUTIL_BIN="$BIN_DIR/plutil" \
  SHASUM_BIN="$BIN_DIR/shasum" \
  RUBY_BIN="$(command -v ruby)" \
  REALPATH_BIN="$(command -v realpath)" \
  bash "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh" "$expected" >/dev/null
if ! grep -Fq "hdiutil:attach -plist -nobrowse -readonly $expected" "$LOG" \
  || ! grep -Fq "hdiutil:detach $MOUNT_DIR" "$LOG"; then
  echo "app DMG smoke did not mount read-only and detach" >&2
  exit 1
fi

# Unsafe Applications links are rejected and still detached.
rm "$MOUNT_DIR/Applications"
ln -s ../Applications "$MOUNT_DIR/Applications"
: >"$LOG"
set +e
env \
  COMMAND_LOG="$LOG" FAKE_MOUNT_DIR="$MOUNT_DIR" FAKE_VERSION="$UPDATEBAR_VERSION" \
  FAKE_PUBLIC_KEY="$VALID_KEY" UPDATEBAR_TEST_ALLOW_NON_VOLUMES_MOUNT=1 \
  SPARKLE_PUBLIC_ED_KEY="$VALID_KEY" HDIUTIL_BIN="$BIN_DIR/hdiutil" \
  PLUTIL_BIN="$BIN_DIR/plutil" SHASUM_BIN="$BIN_DIR/shasum" \
  RUBY_BIN="$(command -v ruby)" REALPATH_BIN="$(command -v realpath)" \
  bash "$TEST_ROOT/Scripts/app-dmg-smoke-test.sh" "$expected" >/dev/null 2>&1
unsafe_link_status=$?
set -e
if [[ "$unsafe_link_status" -eq 0 || "$(grep -c "hdiutil:detach $MOUNT_DIR" "$LOG")" -ne 1 ]]; then
  echo "app DMG smoke must reject an unsafe Applications link and detach" >&2
  exit 1
fi
rm "$MOUNT_DIR/Applications"
ln -s /Applications "$MOUNT_DIR/Applications"

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
if [[ "$existing_status" -eq 0 || "$(cat "$expected")" != "$original_dmg" || "$(cat "$expected.sha256")" != "$original_sha" || -s "$LOG" ]]; then
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

echo "build app DMG behavior ok"
