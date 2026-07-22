#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/updatebar-appcast-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$T"' EXIT
R="$T/root"; B="$T/bin"; LOG="$T/calls"; KEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='; PRIVATE='AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
mkdir -p "$R/Scripts" "$R/dist" "$R/.build/artifacts/sparkle/Sparkle/bin" "$B"
cp "$ROOT/Scripts/generate-appcast.sh" "$R/Scripts/generate-appcast.sh" 2>/dev/null || true
cp "$ROOT/version.env" "$R/version.env"
cp "$ROOT/Package.resolved" "$R/Package.resolved"
printf 'dmg bytes\n' >"$R/dist/UpdateBar-0.5.0-macos-arm64.dmg"
hash="$(shasum -a 256 "$R/dist/UpdateBar-0.5.0-macos-arm64.dmg" | awk '{print $1}')"
printf '%s  UpdateBar-0.5.0-macos-arm64.dmg\n' "$hash" >"$R/dist/UpdateBar-0.5.0-macos-arm64.dmg.sha256"

cat >"$B/smoke" <<'SH'
#!/usr/bin/env bash
printf 'smoke:%s\n' "$*" >>"$CALL_LOG"
[[ "${FAIL_SMOKE:-0}" == 0 ]] || exit 31
SH
cat >"$B/codesign" <<'SH'
#!/usr/bin/env bash
printf 'codesign:%s\n' "$*" >>"$CALL_LOG"; [[ "${FAIL_VERIFY:-}" != codesign ]] || exit 32
SH
cat >"$B/spctl" <<'SH'
#!/usr/bin/env bash
printf 'spctl:%s\n' "$*" >>"$CALL_LOG"; [[ "${FAIL_VERIFY:-}" != gatekeeper ]] || exit 33
SH
cat >"$B/xcrun" <<'SH'
#!/usr/bin/env bash
printf 'xcrun:%s\n' "$*" >>"$CALL_LOG"
if [[ "$1" == stapler ]]; then [[ "${FAIL_VERIFY:-}" != staple ]] || exit 34; exit 0; fi
[[ "$1" == swift ]] || exit 90
[[ "${KEY_MISMATCH:-0}" == 0 ]] || exit 35
SH
cat >"$B/file" <<'SH'
#!/usr/bin/env bash
[[ "${BAD_PLATFORM:-0}" == 0 ]] || { echo "$1: data"; exit 0; }
echo "$1: Mach-O 64-bit executable arm64"
SH
cat >"$B/hdiutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'hdiutil:%s\n' "$*" >>"$CALL_LOG"
if [[ "$1" == detach ]]; then exit 0; fi
[[ "${FAIL_HDIUTIL:-0}" == 0 ]] || exit 39
mount=''; prev=''; for a in "$@"; do [[ "$prev" == -mountpoint ]] && mount="$a"; prev="$a"; done
mkdir -p "$mount/UpdateBar.app/Contents"; printf plist >"$mount/UpdateBar.app/Contents/Info.plist"
reported="$mount"; [[ "${BAD_MOUNT:-0}" == 0 ]] || reported=/tmp/evil
printf '<plist><array><dict><key>mount-point</key><string>%s</string></dict></array></plist>\n' "$reported"
SH
cat >"$B/plutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
key="$2"
case "$key" in
  CFBundleShortVersionString) [[ "${BAD_PLIST:-}" != version ]] && echo 0.5.0 || echo 9.9.9;;
  CFBundleVersion) [[ "${BAD_PLIST:-}" != build ]] && echo 0.5.0 || echo abc;;
  SUFeedURL) [[ "${BAD_PLIST:-}" != feed ]] && echo https://updates.updatebar.sonim1.com/appcast.xml || echo https://evil.example/appcast.xml;;
  SUPublicEDKey) [[ "${BAD_PLIST:-}" != key ]] && echo AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= || echo BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=;;
  *) exit 90;;
esac
SH
cat >"$R/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'appcast:' >>"$CALL_LOG"; printf '%q ' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
keyfile=''; out=''; dir=''; prev=''
for arg in "$@"; do [[ "$prev" == --ed-key-file ]] && keyfile="$arg"; [[ "$prev" == -o ]] && out="$arg"; prev="$arg"; dir="$arg"; done
if [[ -n "$keyfile" ]]; then
  [[ -z "${SPARKLE_PRIVATE_ED_KEY+x}" && -z "${PRIVATE_KEY+x}" ]] || exit 38
  stat -f '%Lp' "$keyfile" >"${CALL_LOG}.mode"; printf '%s' "$keyfile" >"${CALL_LOG}.keypath"; grep -Fq "$EXPECTED_PRIVATE" "$keyfile" || exit 36
fi
[[ "${FAIL_TOOL:-0}" == 0 ]] || exit 37
dmg="$dir/UpdateBar-0.5.0-macos-arm64.dmg"; length="$(stat -f '%z' "$dmg")"
case "${BAD_XML:-}" in malformed) printf '<rss' >"$out"; exit 0;; multi) extra='<enclosure url="x" />';; wrong) version=9.9.9;; unsafe-url) url='https://evil.example/file.dmg';; wrong-length) length=999;; esac
version="${version:-0.5.0}"
url="${url:-https://updates.updatebar.sonim1.com/UpdateBar-0.5.0-macos-arm64.dmg}"
cat >"$out" <<XML
<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="$url" length="$length" sparkle:version="$version" sparkle:shortVersionString="$version" sparkle:edSignature="Q0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQw==" />${extra:-}</item></channel></rss>
XML
SH
chmod +x "$B"/* "$R/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

run_case() {
  local name="$1" expected="$2"; shift 2; rm -rf "$R/dist/updates"; : >"$LOG"
  [[ "$name" != dest-conflict ]] || ln -s "$T/elsewhere" "$R/dist/updates"
  set +e
  env CALL_LOG="$LOG" EXPECTED_PRIVATE="$PRIVATE" SPARKLE_PUBLIC_ED_KEY="$KEY" APP_DMG_SMOKE_BIN="$B/smoke" CODESIGN_BIN="$B/codesign" SPCTL_BIN="$B/spctl" XCRUN_BIN="$B/xcrun" FILE_BIN="$B/file" HDIUTIL_BIN="$B/hdiutil" PLUTIL_BIN="$B/plutil" "$@" "$R/Scripts/generate-appcast.sh" >"$T/$name.out" 2>&1
  status=$?; set -e
  [[ "$status" == "$expected" ]] || { cat "$T/$name.out" >&2; echo "$name expected $expected got $status" >&2; exit 1; }
}

# RED: copied implementation is absent before production script exists.
run_case keychain 0
test -f "$R/dist/updates/appcast.xml"
grep -Fq -- '--account updatebar' "$LOG"
run_case ci 0 SPARKLE_PRIVATE_ED_KEY="$PRIVATE"
[[ "$(cat "$LOG.mode")" == 600 ]]
! grep -Fq "$PRIVATE" "$LOG" "$T/ci.out"
test ! -e "$(cat "$LOG.keypath")"
run_case key-mismatch 35 SPARKLE_PRIVATE_ED_KEY="$PRIVATE" KEY_MISMATCH=1
test ! -e "$R/dist/updates/appcast.xml"
run_case invalid-private 64 SPARKLE_PRIVATE_ED_KEY=not-base64
run_case invalid-public 64 SPARKLE_PUBLIC_ED_KEY=not-base64
run_case dmg-signature 31 FAIL_SMOKE=1
run_case dmg-plist-feed-key-version 31 FAIL_SMOKE=1
run_case codesign 32 FAIL_VERIFY=codesign
run_case staple 34 FAIL_VERIFY=staple
run_case gatekeeper 33 FAIL_VERIFY=gatekeeper
run_case metadata-mount 39 FAIL_HDIUTIL=1
run_case unsafe-mount 1 BAD_MOUNT=1
run_case plist-version 1 BAD_PLIST=version
run_case plist-build 1 BAD_PLIST=build
run_case plist-feed 1 BAD_PLIST=feed
run_case plist-key 1 BAD_PLIST=key
run_case tool 37 FAIL_TOOL=1
run_case malformed 1 BAD_XML=malformed
run_case multi 1 BAD_XML=multi
run_case wrong 1 BAD_XML=wrong
run_case unsafe-url 1 BAD_XML=unsafe-url
run_case wrong-length 1 BAD_XML=wrong-length
run_case platform 66 BAD_PLATFORM=1
run_case dest-conflict 1
mkdir "$R/dist/.generate-appcast.lock"
run_case concurrent-output 1
rmdir "$R/dist/.generate-appcast.lock"

cp "$R/dist/UpdateBar-0.5.0-macos-arm64.dmg" "$T/dmg"
printf 'wrong\n' >"$R/dist/UpdateBar-0.5.0-macos-arm64.dmg"
run_case checksum-mismatch 1
cp "$T/dmg" "$R/dist/UpdateBar-0.5.0-macos-arm64.dmg"
printf 'UPDATEBAR_VERSION=0.5.0\nEXTRA=1\n' >"$R/version.env"
run_case invalid-version-file 64
cp "$ROOT/version.env" "$R/version.env"

mkdir "$R/.build/artifacts/sparkle/Sparkle/alternate"
cp "$R/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" "$R/.build/artifacts/sparkle/Sparkle/alternate/generate_appcast"
chmod +x "$R/.build/artifacts/sparkle/Sparkle/alternate/generate_appcast"
run_case ambiguous-tool 66
rm -rf "$R/.build/artifacts/sparkle/Sparkle/alternate"
rm "$R/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
run_case missing-tool 66
echo "generate appcast tests passed"
