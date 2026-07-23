#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"

VALID_SPARKLE_KEY="MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "$*" >&2
  exit 1
}

make_framework() {
  local root="$1"
  local framework="$root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
  mkdir -p \
    "$framework/Versions/B/Updater.app/Contents/MacOS" \
    "$framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS" \
    "$framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS"
  for executable in \
    "$framework/Versions/B/Sparkle" \
    "$framework/Versions/B/Autoupdate" \
    "$framework/Versions/B/Updater.app/Contents/MacOS/Updater" \
    "$framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
    "$framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"; do
    printf '#!/usr/bin/env sh\nexit 0\n' >"$executable"
    chmod 755 "$executable"
  done
}

prepare_case() {
  local name="$1"
  CASE_ROOT="$TMP_DIR/$name/root"
  BIN_DIR="$TMP_DIR/$name/bin"
  LOG_DIR="$TMP_DIR/$name/logs"
  mkdir -p "$CASE_ROOT/Scripts" "$CASE_ROOT/Assets/AppIcon" "$BIN_DIR" "$LOG_DIR"

  cp "$ROOT/Scripts/package-app.sh" "$CASE_ROOT/Scripts/package-app.sh"
  cp "$ROOT/Assets/AppIcon/UpdateBar.icns" "$CASE_ROOT/Assets/AppIcon/UpdateBar.icns"
  cp "$ROOT/version.env" "$CASE_ROOT/version.env"

  cat >"$CASE_ROOT/Scripts/generate-version-source.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SH
  chmod +x "$CASE_ROOT/Scripts/generate-version-source.sh"

  cat >"$BIN_DIR/uname" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'x86_64\n' ;;
  *) /usr/bin/uname "$@" ;;
esac
SH

  cat >"$BIN_DIR/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${SWIFT_LOG:?}"
if [[ "${SWIFT_FAIL_STATUS:-0}" != "0" && "$*" == *"build"* ]]; then
  exit "$SWIFT_FAIL_STATUS"
fi
case "$*" in
  "package resolve") exit 0 ;;
  *"--product updatebar-menubar"*)
    mkdir -p .build/release
    cat >.build/release/updatebar-menubar <<'BIN'
#!/usr/bin/env sh
exit 0
BIN
    chmod 755 .build/release/updatebar-menubar
    ;;
  *"--product updatebar"*)
    mkdir -p .build/release
    cat >.build/release/updatebar <<'BIN'
#!/usr/bin/env sh
if [ "${1:-}" = "--version" ]; then
  echo fixture
fi
exit 0
BIN
    chmod 755 .build/release/updatebar
    ;;
  *)
    echo "unexpected swift invocation: $*" >&2
    exit 1
    ;;
esac
SH

  cat >"$BIN_DIR/plutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${PLUTIL_LOG:?}"
if [[ "${PLUTIL_FAIL_STATUS:-0}" != "0" ]]; then
  exit "$PLUTIL_FAIL_STATUS"
fi
if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
  exec /usr/bin/plutil "$@"
fi
[[ "$(/usr/bin/uname -s)" == Linux ]] || exit 90
/usr/bin/ruby -rrexml/document -rrexml/formatters/default - "$@" <<'RUBY'
args=ARGV
begin
  insert=args.length==5&&args[0]=="-insert"&&["-string","-bool"].include?(args[2])
  lint=args.length==2&&args[0]=="-lint"
  extract=args.length==6&&args[0]=="-extract"&&args[2,3]==["raw","-o","-"]
  exit 90 unless insert||lint||extract
  raw=File.binread(args[-1])
  canonical_doctype='<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  doctype_count=raw.scan("<!DOCTYPE").length
  exit 1 unless doctype_count==0||(doctype_count==1&&raw.include?(canonical_doctype))
  document=REXML::Document.new(raw)
  root=document.root
  children=root&.elements&.to_a
  exit 1 unless root&.name=="plist"&&children&.length==1&&children[0].name=="dict"
  dict=children[0]
  entries=dict.elements.to_a
  exit 1 unless entries.length.even?
  pairs={}
  entries.each_slice(2) do |key_element,value_element|
    exit 1 unless key_element.name=="key"
    key_children=key_element.children
    exit 1 unless key_children.all?{|child|child.is_a?(REXML::Text)}
    key=key_children.map(&:value).join
    exit 1 if pairs.key?(key)
    case value_element.name
    when "string"
      value_children=value_element.children
      exit 1 unless value_children.all?{|child|child.is_a?(REXML::Text)}
      value=value_children.map(&:value).join
    when "true","false"
      exit 1 unless value_element.children.empty?
      value=value_element.name
    else
      exit 1
    end
    pairs[key]=value
  end
  if insert
    exit 1 if pairs.key?(args[1])
    exit 1 if args[2]=="-bool"&&!["true","false"].include?(args[3])
    key=REXML::Element.new("key")
    key.text=args[1]
    value=REXML::Element.new(args[2]=="-string" ? "string" : args[3])
    value.text=args[3] if args[2]=="-string"
    dict.add_element(key)
    dict.add_element(value)
    File.open(args[4],"wb"){|file|REXML::Formatters::Default.new.write(document,file)}
  elsif lint
    exit 0
  elsif extract
    exit 1 unless pairs.key?(args[1])
    print pairs[args[1]]
  end
rescue REXML::ParseException,SystemCallError
  exit 1
end
RUBY
SH

  cat >"$BIN_DIR/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${CODESIGN_LOG:?}"
SH

  cat >"$BIN_DIR/ditto" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${DITTO_LOG:?}"
if [[ "${DITTO_FAIL_STATUS:-0}" != "0" ]]; then
  exit "$DITTO_FAIL_STATUS"
fi
if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
  exec /usr/bin/ditto "$@"
fi
[[ $# == 2 && -d "$1" && ! -e "$2" ]] || exit 90
exec /bin/cp -R "$1" "$2"
SH

  cat >"$BIN_DIR/otool" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${OTOOL_LOG:?}"
case "${1:-}" in
  -L)
    printf '%s:\n' "${2:-UpdateBar}"
    printf '\t@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.0.0, current version 2.9.4)\n'
    ;;
  -l)
    cat <<'OUT'
Load command 1
          cmd LC_RPATH
      cmdsize 48
         path @executable_path/../Frameworks (offset 12)
OUT
    ;;
  *) exit 2 ;;
esac
SH

  chmod +x "$BIN_DIR/uname" "$BIN_DIR/swift" "$BIN_DIR/plutil" \
    "$BIN_DIR/codesign" "$BIN_DIR/ditto" "$BIN_DIR/otool"
  make_framework "$CASE_ROOT"
}

run_package() {
  (
    cd "$CASE_ROOT"
    env \
      PATH="$BIN_DIR:$PATH" \
      SWIFT_LOG="$LOG_DIR/swift.log" \
      PLUTIL_LOG="$LOG_DIR/plutil.log" \
      CODESIGN_LOG="$LOG_DIR/codesign.log" \
      DITTO_LOG="$LOG_DIR/ditto.log" \
      OTOOL_LOG="$LOG_DIR/otool.log" \
      SPARKLE_PUBLIC_ED_KEY="$VALID_SPARKLE_KEY" \
      UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 \
      "$@" \
      bash Scripts/package-app.sh
  )
}

run_plutil_fixture() {
  PLUTIL_LOG="$LOG_DIR/plutil.log" PLUTIL_FAIL_STATUS=0 \
    "$BIN_DIR/plutil" "$@"
}

plist_value() {
  run_plutil_fixture -extract "$1" raw -o - "$2"
}

expect_failure() {
  local description="$1"
  shift
  local output
  if output="$(run_package "$@" 2>&1)"; then
    fail "$description should fail"
  fi
  printf '%s' "$output"
}

expect_failure_status() {
  local description="$1"
  local expected_status="$2"
  shift 2
  local output_file="$LOG_DIR/expected-failure.out"
  local status=0
  set +e
  run_package "$@" >"$output_file" 2>&1
  status=$?
  set -e
  if [[ "$status" == "0" ]]; then
    fail "$description should fail"
  fi
  if [[ "$status" != "$expected_status" ]]; then
    fail "$description should exit $expected_status (got $status)"
  fi
  cat "$output_file"
}

assert_no_build_or_sign() {
  if [[ -s "$LOG_DIR/swift.log" ]] && grep -Fq " build " "$LOG_DIR/swift.log"; then
    fail "validation failure must happen before swift build"
  fi
  if [[ -s "$LOG_DIR/codesign.log" ]]; then
    fail "validation failure must happen before codesign"
  fi
}

if [[ "$(/usr/bin/uname -s)" == Linux ]]; then
  prepare_case portable-tool-contract
  valid_plist="$CASE_ROOT/valid.plist"
  malformed_plist="$CASE_ROOT/malformed.plist"
  nested_plist="$CASE_ROOT/nested.plist"
  duplicate_plist="$CASE_ROOT/duplicate.plist"
  doctype_plist="$CASE_ROOT/doctype.plist"
  printf '%s\n' '<plist><dict><key>A</key><string>B</string></dict></plist>' >"$valid_plist"
  printf '%s\n' '<plist><dict><key>A</key><string>B</string>' >"$malformed_plist"
  printf '%s\n' '<plist><dict><key>A</key><string>B<evil/></string></dict></plist>' >"$nested_plist"
  printf '%s\n' '<plist><dict><key>A</key><string>B</string><key>A</key><string>C</string></dict></plist>' >"$duplicate_plist"
  printf '%s\n' '<!DOCTYPE plist [<!ENTITY x "B">]><plist><dict><key>A</key><string>&x;</string></dict></plist>' >"$doctype_plist"
  run_plutil_fixture -lint "$valid_plist" >/dev/null
  for invalid_plist in "$malformed_plist" "$nested_plist" "$duplicate_plist" "$doctype_plist"; do
    if run_plutil_fixture -lint "$invalid_plist" >/dev/null 2>&1; then
      fail "Linux plutil fixture accepted an unsafe property list: $invalid_plist"
    fi
  done

  ditto_source="$CASE_ROOT/ditto-source"
  ditto_destination="$CASE_ROOT/ditto-destination"
  mkdir "$ditto_source"
  printf 'copied\n' >"$ditto_source/file"
  set +e
  DITTO_LOG="$LOG_DIR/ditto.log" DITTO_FAIL_STATUS=0 "$BIN_DIR/ditto" "$ditto_source" >/dev/null 2>&1
  status=$?
  set -e
  [[ "$status" == 90 ]] || fail "Linux ditto fixture should reject unexpected arguments (got $status)"
  DITTO_LOG="$LOG_DIR/ditto.log" DITTO_FAIL_STATUS=0 \
    "$BIN_DIR/ditto" "$ditto_source" "$ditto_destination"
  [[ "$(<"$ditto_destination/file")" == copied ]] || fail "Linux ditto fixture did not copy the exact source"
fi

prepare_case missing-key
output="$(expect_failure_status "missing Sparkle public key" 64 SPARKLE_PUBLIC_ED_KEY=)"
[[ "$output" == *"SPARKLE_PUBLIC_ED_KEY"* ]] || fail "missing-key error should name SPARKLE_PUBLIC_ED_KEY"
assert_no_build_or_sign

for invalid_feed in "" "http://updates.example.test/appcast.xml" \
  $'https://updates.example.test/appcast.xml\nmalicious' \
  $'https://updates.example.test/appcast.xml\x01malicious'; do
  prepare_case "invalid-feed-${RANDOM}"
  output="$(expect_failure_status "invalid update feed" 64 UPDATEBAR_UPDATE_FEED_URL="$invalid_feed")"
  [[ "$output" == *"UPDATEBAR_UPDATE_FEED_URL"* ]] || fail "invalid-feed error should name UPDATEBAR_UPDATE_FEED_URL"
  assert_no_build_or_sign
done

for invalid_key in \
  "not-a-valid-key" \
  "c2hvcnQ=" \
  "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY" \
  "$VALID_SPARKLE_KEY"$'\n' \
  "$VALID_SPARKLE_KEY"$'\x01'; do
  prepare_case "invalid-key-${RANDOM}"
  output="$(expect_failure_status "invalid Sparkle public key" 64 SPARKLE_PUBLIC_ED_KEY="$invalid_key")"
  [[ "$output" == *"SPARKLE_PUBLIC_ED_KEY"* ]] || fail "invalid-key error should name SPARKLE_PUBLIC_ED_KEY"
  assert_no_build_or_sign
done

prepare_case key-validator-failure
cat >"$BIN_DIR/ruby-fail" <<'SH'
#!/usr/bin/env bash
exit 47
SH
chmod +x "$BIN_DIR/ruby-fail"
expect_failure_status "Sparkle key validator tool failure" 47 RUBY_BIN="$BIN_DIR/ruby-fail" >/dev/null
assert_no_build_or_sign

prepare_case missing-identity
output="$(expect_failure "missing signing identity" UPDATEBAR_SIGN_APP=1 DEVELOPER_ID_APPLICATION= UPDATEBAR_SIGN_IDENTITY=)"
[[ "$output" == *"DEVELOPER_ID_APPLICATION"* ]] || fail "missing-identity error should name the preferred variable"
assert_no_build_or_sign

prepare_case missing-framework
rm -rf "$CASE_ROOT/.build/artifacts/sparkle/Sparkle"
output="$(expect_failure "missing Sparkle framework")"
[[ "$output" == *"Sparkle.framework"* ]] || fail "missing-framework error should name Sparkle.framework"
assert_no_build_or_sign
[[ ! -e "$CASE_ROOT/dist/UpdateBar.app" ]] || fail "missing framework must not leave a partial app"

prepare_case ambiguous-framework
mkdir -p "$CASE_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle-copy.xcframework/macos-arm64_x86_64"
cp -R \
  "$CASE_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
  "$CASE_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle-copy.xcframework/macos-arm64_x86_64/Sparkle.framework"
output="$(expect_failure "ambiguous Sparkle framework")"
[[ "$output" == *"exactly one"* ]] || fail "ambiguous-framework error should explain uniqueness"
assert_no_build_or_sign

prepare_case symlink-framework
rm -rf "$CASE_ROOT/.build/artifacts/sparkle/Sparkle"
mkdir -p "$CASE_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
mkdir -p "$TMP_DIR/outside/Sparkle.framework"
ln -s "$TMP_DIR/outside/Sparkle.framework" \
  "$CASE_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
expect_failure "symlink Sparkle framework" >/dev/null
assert_no_build_or_sign

prepare_case missing-helper
rm -rf "$CASE_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
expect_failure "missing nested Sparkle helper" UPDATEBAR_SIGN_APP=1 DEVELOPER_ID_APPLICATION="Developer ID Application: Test" >/dev/null
if [[ -s "$LOG_DIR/codesign.log" ]]; then
  fail "all Sparkle signing targets must be validated before the first codesign call"
fi

prepare_case swift-failure
set +e
run_package SWIFT_FAIL_STATUS=42 >/dev/null 2>"$LOG_DIR/failure.err"
status=$?
set -e
[[ "$status" == "42" ]] || fail "swift failure status should propagate (got $status)"
[[ ! -s "$LOG_DIR/codesign.log" ]] || fail "swift failure must not sign"
if grep -Fq "$VALID_SPARKLE_KEY" "$LOG_DIR/failure.err"; then
  fail "failure output must not leak the Sparkle public key"
fi

prepare_case ditto-failure
set +e
run_package DITTO_FAIL_STATUS=43 >/dev/null 2>"$LOG_DIR/failure.err"
status=$?
set -e
[[ "$status" == "43" ]] || fail "ditto failure status should propagate (got $status)"
[[ ! -e "$CASE_ROOT/dist/UpdateBar.app" ]] || fail "ditto failure must not leave a partial final app"
[[ ! -s "$LOG_DIR/codesign.log" ]] || fail "ditto failure must not sign"

prepare_case plutil-failure
set +e
run_package PLUTIL_FAIL_STATUS=44 >/dev/null 2>"$LOG_DIR/failure.err"
status=$?
set -e
[[ "$status" == "44" ]] || fail "plutil failure status should propagate (got $status)"
[[ ! -e "$CASE_ROOT/dist/UpdateBar.app" ]] || fail "plutil failure must not leave a partial final app"
[[ ! -s "$LOG_DIR/codesign.log" ]] || fail "plutil failure must not sign"

prepare_case escaping-symlink
mkdir -p "$CASE_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/Resources"
ln -s "$TMP_DIR" \
  "$CASE_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/Resources/escape"
output="$(expect_failure "framework symlink escaping the bundle")"
[[ "$output" == *"outside"* ]] || fail "escaping symlink error should explain bundle confinement"
[[ ! -e "$CASE_ROOT/dist/UpdateBar.app" ]] || fail "escaping symlink must not leave a partial final app"
[[ ! -s "$LOG_DIR/codesign.log" ]] || fail "escaping symlink must fail before signing"

prepare_case unsigned
run_package >/dev/null
UNSIGNED_APP="$CASE_ROOT/dist/UpdateBar.app"
UNSIGNED_PLIST="$UNSIGNED_APP/Contents/Info.plist"
[[ -d "$UNSIGNED_APP/Contents/Frameworks/Sparkle.framework" ]] || \
  fail "unsigned packaging should copy Sparkle.framework"
unsigned_feed="$(plist_value SUFeedURL "$UNSIGNED_PLIST")"
unsigned_key="$(plist_value SUPublicEDKey "$UNSIGNED_PLIST")"
unsigned_automatic="$(plist_value SUEnableAutomaticChecks "$UNSIGNED_PLIST")"
[[ "$unsigned_feed" == "https://updates.updatebar.sonim1.com/appcast.xml" ]] || \
  fail "unsigned package has unexpected SUFeedURL"
[[ "$unsigned_key" == "$VALID_SPARKLE_KEY" ]] || fail "unsigned package has unexpected SUPublicEDKey"
[[ "$unsigned_automatic" == "false" ]] || fail "unsigned package must disable automatic checks"
[[ ! -s "$LOG_DIR/codesign.log" ]] || fail "unsigned packaging must not call codesign"

prepare_case signed
run_package \
  UPDATEBAR_SIGN_APP=1 \
  DEVELOPER_ID_APPLICATION="Developer ID Application: Preferred" \
  UPDATEBAR_SIGN_IDENTITY="Developer ID Application: Legacy" \
  UPDATEBAR_NOTARIZE_APP=1 >/dev/null

APP="$CASE_ROOT/dist/UpdateBar.app"
PLIST="$APP/Contents/Info.plist"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$FRAMEWORK" ]] || fail "package app should copy Sparkle.framework"
[[ -f "$APP/Contents/Resources/UpdateBar.icns" ]] || fail "package app should copy UpdateBar.icns"

feed="$(plist_value SUFeedURL "$PLIST")"
key="$(plist_value SUPublicEDKey "$PLIST")"
automatic="$(plist_value SUEnableAutomaticChecks "$PLIST")"
[[ "$feed" == "https://updates.updatebar.sonim1.com/appcast.xml" ]] || fail "unexpected SUFeedURL: $feed"
[[ "$key" == "$VALID_SPARKLE_KEY" ]] || fail "unexpected SUPublicEDKey"
[[ "$automatic" == "false" ]] || fail "SUEnableAutomaticChecks must be boolean false"

grep -Fq -- "-Xlinker -rpath -Xlinker @executable_path/../Frameworks" "$LOG_DIR/swift.log" || \
  fail "menu app build must add the embedded-framework runtime path"
grep -Fq -- "-L dist/.UpdateBar.app.tmp." "$LOG_DIR/otool.log" || \
  fail "package app should inspect the executable's Sparkle dependency"
grep -Fq -- "-l dist/.UpdateBar.app.tmp." "$LOG_DIR/otool.log" || \
  fail "package app should inspect the executable's runtime paths"

if grep -F -- "--deep" "$LOG_DIR/codesign.log" >/dev/null; then
  fail "package-app signing must not use codesign --deep"
fi
sign_count="$(grep -c -- '--sign' "$LOG_DIR/codesign.log")"
[[ "$sign_count" == "8" ]] || fail "package-app should make exactly eight inside-out signing calls (got $sign_count)"

expected_targets=(
  "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
  "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
  "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
  "Contents/Frameworks/Sparkle.framework"
  "Contents/Resources/updatebar"
  "Contents/MacOS/UpdateBar"
  "dist/.UpdateBar.app.tmp."
)
index=1
for target in "${expected_targets[@]}"; do
  line="$(sed -n "${index}p" "$LOG_DIR/codesign.log")"
  [[ "$line" == *"$target"* ]] || fail "codesign call $index should target $target; got: $line"
  [[ "$line" == *"--force"* && "$line" == *"--options runtime"* && "$line" == *"--timestamp"* ]] || \
    fail "codesign call $index is missing hardened runtime options"
  [[ "$line" == *"--sign Developer ID Application: Preferred"* ]] || \
    fail "DEVELOPER_ID_APPLICATION must take precedence over UPDATEBAR_SIGN_IDENTITY"
  index=$((index + 1))
done

if [[ -s "$LOG_DIR/xcrun.log" ]]; then
  fail "package-app must not notarize the app bundle"
fi
if grep -Fq -- '-c -k' "$LOG_DIR/ditto.log"; then
  fail "package-app must not create an app notarization archive"
fi

echo "package app Sparkle bundling and signing behavior ok"
