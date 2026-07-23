#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; SOURCE="$ROOT/Scripts/publish-release.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ -x "$SOURCE" ]] || fail "publish-release.sh is missing or not executable"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-publish-release-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/project"; B="$TMP/bin"; A="$TMP/assets"; STATE="$TMP/state"; ORDER="$TMP/order"; GHLOG="$TMP/gh"; R2_CAPTURE="$TMP/r2-capture"; COMMIT=0123456789abcdef0123456789abcdef01234567
mkdir -p "$P/Scripts" "$P/dist/updates" "$B" "$A"; cp "$SOURCE" "$P/Scripts/publish-release.sh"; chmod +x "$P/Scripts/publish-release.sh"

cat >"$B/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
 'remote get-url origin') printf '%s\n' "${FAKE_ORIGIN:-git@github.com:sonim1/UpdateBar.git}";;
 'rev-parse HEAD') printf '%s\n' "${FAKE_HEAD:-0123456789abcdef0123456789abcdef01234567}";;
 'rev-parse --verify refs/tags/v1.2.3^{commit}') printf '%s\n' "${FAKE_TAG:-0123456789abcdef0123456789abcdef01234567}";;
 *) exit 90;;
esac
EOF
cat >"$B/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${GH_REPO:-}" == sonim1/UpdateBar && "${GH_HOST:-}" == github.com ]] || exit 70
printf '%q ' "$@" >>"$GH_LOG"; printf '\n' >>"$GH_LOG"
state=absent; [[ ! -f "$GH_STATE" ]] || state="$(cat "$GH_STATE")"
if [[ "$1" == api ]]; then
  [[ "$*" == 'api --hostname github.com --include --silent repos/sonim1/UpdateBar/releases/tags/v1.2.3' ]] || exit 71
  if [[ "$state" == absent ]]; then printf 'HTTP/2.0 404 Not Found\n'; exit 1; fi
  printf 'HTTP/2.0 200 OK\n'; exit 0
fi
[[ "$1" == release ]] || exit 72
case "$2" in
 create)
  [[ "$*" == 'release create v1.2.3 --repo sonim1/UpdateBar --draft --verify-tag --generate-notes --title UpdateBar 1.2.3' ]] || exit 73
  printf 'create\n' >>"$ORDER"; [[ "${FAKE_CREATE_STATUS:-0}" == 0 ]] || exit "$FAKE_CREATE_STATUS"; printf draft >"$GH_STATE";;
 view)
  [[ "$3" == v1.2.3 && "$4" == --repo && "$5" == sonim1/UpdateBar ]] || exit 74
  [[ "$state" != absent ]] || exit 75
  if [[ "$*" == *'--json isDraft --jq .isDraft' ]]; then [[ "$state" == draft ]] && echo true || echo false
  elif [[ "$*" == *'--json assets --jq .assets[].name' ]]; then for f in "$GH_ASSETS"/*; do [[ -e "$f" ]] && basename "$f"; done; [[ -z "${EXTRA_NAMES:-}" ]] || printf '%s\n' "$EXTRA_NAMES"
  else exit 76; fi;;
 upload)
  # gh release upload TAG FILE --repo REPO
  [[ "$3" == v1.2.3 && "$5" == --repo && "$6" == sonim1/UpdateBar && -f "$4" ]] || exit 78
  printf 'upload %s\n' "$(basename "$4")" >>"$ORDER"; [[ "${FAKE_UPLOAD_STATUS:-0}" == 0 ]] || exit "$FAKE_UPLOAD_STATUS"; cp "$4" "$GH_ASSETS/$(basename "$4")";;
 download)
  [[ "$3" == v1.2.3 && "$4" == --repo && "$5" == sonim1/UpdateBar && "$6" == --pattern && "$8" == --dir ]] || exit 79
  [[ -f "$GH_ASSETS/$7" ]] || exit 80; cp "$GH_ASSETS/$7" "$9/$7";;
 edit)
  [[ "$*" == 'release edit v1.2.3 --repo sonim1/UpdateBar --draft=false' ]] || exit 81
  printf 'publish-github\n' >>"$ORDER"; [[ "${FAKE_EDIT_STATUS:-0}" == 0 ]] || exit "$FAKE_EDIT_STATUS"; printf published >"$GH_STATE";;
 *) exit 82;;
esac
EOF
cat >"$P/Scripts/publish-update.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 0 ]] || exit 90
printf 'publish-r2\n' >>"$ORDER"
artifact_dir="${UPDATE_ARTIFACT_DIR:-$LIVE_UPDATE_DIR}"
if [[ "${CONCURRENT_REPLACE:-0}" == 1 ]]; then
  printf 'replacement dmg\n' >"$LIVE_UPDATE_DIR/$DMG_NAME"
  printf '%064d  %s\n' 0 "$DMG_NAME" >"$LIVE_UPDATE_DIR/$DMG_NAME.sha256"
  entries="$(find "$artifact_dir" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | sort)"
  expected="$(printf '%s\n' "$DMG_NAME" "$DMG_NAME.sha256" appcast.xml | sort)"
  [[ "$artifact_dir" != "$LIVE_UPDATE_DIR" && "$entries" == "$expected" ]] || exit 91
  cp "$artifact_dir/$DMG_NAME" "$R2_CAPTURE"
fi
exit "${FAKE_R2_STATUS:-0}"
EOF
chmod +x "$B"/* "$P/Scripts/publish-update.sh"

checksum(){ local path="$1" name="$(basename "$1")"; printf '%s  %s\n' "$(/usr/bin/shasum -a 256 "$path"|awk '{print $1}')" "$name" >"$path.sha256"; }
write_files(){
  rm -rf "$P/dist"; mkdir -p "$P/dist/updates"
  MAC=updatebar-1.2.3-macos-arm64.tar.gz; LINUX=updatebar-1.2.3-linux-x86_64.tar.gz; DMG=UpdateBar-1.2.3-macos-arm64.dmg
  printf mac >"$P/dist/$MAC"; checksum "$P/dist/$MAC"; printf linux >"$P/dist/$LINUX"; checksum "$P/dist/$LINUX"; printf dmg >"$P/dist/$DMG"; checksum "$P/dist/$DMG"
  cp "$P/dist/$DMG" "$P/dist/updates/$DMG"; cp "$P/dist/$DMG.sha256" "$P/dist/updates/$DMG.sha256"
  length="$(stat -f %z "$P/dist/$DMG")"
  cat >"$P/dist/updates/appcast.xml" <<EOF
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://updates.updatebar.sonim1.com/$DMG" length="$length" sparkle:version="12" sparkle:shortVersionString="1.2.3" sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="/></item></channel></rss>
EOF
  msh="$(/usr/bin/shasum -a 256 "$P/dist/$MAC"|awk '{print $1}')"; dsh="$(/usr/bin/shasum -a 256 "$P/dist/$DMG"|awk '{print $1}')"
  cat >"$P/dist/release-manifest.json" <<EOF
{"schemaVersion":1,"repository":"sonim1/UpdateBar","tag":"v1.2.3","version":"1.2.3","commit":"$COMMIT","packages":[{"type":"formula","token":"updatebar","source":{"kind":"release-asset","name":"$MAC","sha256":"$msh"}},{"type":"cask","token":"updatebar-app","source":{"kind":"release-asset","name":"$DMG","sha256":"$dsh"}},{"type":"formula","token":"updatebar-tui","source":{"kind":"github-tag-archive","sha256":"$(printf '%064d' 1)"}}]}
EOF
}
reset(){ rm -f "$STATE" "$A"/* "$R2_CAPTURE"; : >"$ORDER"; : >"$GHLOG"; FAKE_UPLOAD_STATUS=0; FAKE_EDIT_STATUS=0; FAKE_R2_STATUS=0; FAKE_CREATE_STATUS=0; FAKE_ORIGIN='git@github.com:sonim1/UpdateBar.git'; FAKE_HEAD="$COMMIT"; FAKE_TAG="$COMMIT"; EXTRA_NAMES=''; CONCURRENT_REPLACE=0; write_files; }
run(){ set +e; output="$(GIT_BIN="$B/git" GH_BIN="$B/gh" CMP_BIN=/usr/bin/cmp RUBY_BIN=/usr/bin/ruby PUBLISH_UPDATE_SCRIPT="$P/Scripts/publish-update.sh" GH_STATE="$STATE" GH_ASSETS="$A" GH_LOG="$GHLOG" ORDER="$ORDER" R2_CAPTURE="$R2_CAPTURE" LIVE_UPDATE_DIR="$P/dist/updates" DMG_NAME="$DMG" CONCURRENT_REPLACE="$CONCURRENT_REPLACE" FAKE_UPLOAD_STATUS="$FAKE_UPLOAD_STATUS" FAKE_EDIT_STATUS="$FAKE_EDIT_STATUS" FAKE_R2_STATUS="$FAKE_R2_STATUS" FAKE_CREATE_STATUS="$FAKE_CREATE_STATUS" FAKE_ORIGIN="$FAKE_ORIGIN" FAKE_HEAD="$FAKE_HEAD" FAKE_TAG="$FAKE_TAG" EXTRA_NAMES="$EXTRA_NAMES" GH_REPO=attacker/repo GH_HOST=evil.invalid "$P/Scripts/publish-release.sh" "$@" 2>&1)"; status=$?; set -e; }

required=(updatebar-1.2.3-macos-arm64.tar.gz updatebar-1.2.3-macos-arm64.tar.gz.sha256 updatebar-1.2.3-linux-x86_64.tar.gz updatebar-1.2.3-linux-x86_64.tar.gz.sha256 UpdateBar-1.2.3-macos-arm64.dmg UpdateBar-1.2.3-macos-arm64.dmg.sha256 appcast.xml release-manifest.json)
reset; run v1.2.3; [[ "$status" == 0 ]] || fail "new release failed ($status): $output"
for n in "${required[@]}"; do [[ -f "$A/$n" ]] || fail "missing uploaded $n"; done
[[ "$(tail -2 "$ORDER")" == $'publish-r2\npublish-github' ]] || fail "publication order wrong: $(cat "$ORDER")"
! grep -Fq -- --clobber "$GHLOG" || fail "publisher used clobber"

# A byte-identical draft rerun compares instead of overwriting; a published rerun is also immutable.
printf draft >"$STATE"; : >"$ORDER"; run v1.2.3; [[ "$status" == 0 ]] || fail "draft rerun failed: $output"; ! grep -q '^upload ' "$ORDER" || fail "rerun reuploaded assets"
printf published >"$STATE"; : >"$ORDER"; run v1.2.3; [[ "$status" == 0 ]] || fail "published rerun failed: $output"; [[ "$(cat "$ORDER")" == publish-r2 ]] || fail "published release was mutated"

# Unknown remote assets make both draft and published releases invalid before mutation/R2.
for remote_state in draft published; do
  reset; printf '%s' "$remote_state" >"$STATE"
  for n in "${required[@]}"; do cp "$P/dist/$n" "$A/$n" 2>/dev/null || cp "$P/dist/updates/$n" "$A/$n"; done
  EXTRA_NAMES='unexpected-debug-symbols.zip'; run v1.2.3
  [[ "$status" != 0 && "$output" == *unexpected* && ! -s "$ORDER" ]] || fail "$remote_state release accepted an extra asset or mutated: $output / $(cat "$ORDER")"
done
for remote_state in draft published; do
  reset; printf '%s' "$remote_state" >"$STATE"
  for n in "${required[@]}"; do cp "$P/dist/$n" "$A/$n" 2>/dev/null || cp "$P/dist/updates/$n" "$A/$n"; done
  EXTRA_NAMES="${required[0]}"; run v1.2.3
  [[ "$status" != 0 && "$output" == *ambiguous* && ! -s "$ORDER" ]] || fail "$remote_state release accepted a duplicate asset or mutated: $output / $(cat "$ORDER")"
done

reset; printf draft >"$STATE"; for n in "${required[@]}"; do cp "$P/dist/$n" "$A/$n" 2>/dev/null || cp "$P/dist/updates/$n" "$A/$n"; done; printf conflict >"$A/${required[0]}"; run v1.2.3
[[ "$status" != 0 && "$output" == *conflict* ]] || fail "existing byte conflict accepted"; [[ ! -s "$ORDER" ]] || fail "conflict mutated state"

reset; printf published >"$STATE"; for n in "${required[@]:1}"; do cp "$P/dist/$n" "$A/$n" 2>/dev/null || cp "$P/dist/updates/$n" "$A/$n"; done; run v1.2.3
[[ "$status" != 0 && "$output" == *missing* ]] || fail "public release missing asset accepted"; [[ ! -s "$ORDER" ]] || fail "public missing asset mutated state"

reset; /usr/bin/ruby -e 'p=ARGV[0];s=File.read(p);s.sub!(%q{"repository":"sonim1/UpdateBar"},%q{"repository":"evil/repo","repository":"sonim1/UpdateBar"});File.write(p,s)' "$P/dist/release-manifest.json"; run v1.2.3
[[ "$status" == 64 && ! -s "$ORDER" ]] || fail "duplicate manifest key accepted: $output"
reset; /usr/bin/ruby -rjson -e 'p=ARGV[0];d=JSON.parse(File.read(p));d["packages"].pop;File.write(p,JSON.generate(d))' "$P/dist/release-manifest.json"; run v1.2.3
[[ "$status" == 64 && ! -s "$ORDER" ]] || fail "missing manifest package accepted"
reset; /usr/bin/ruby -rjson -e 'p=ARGV[0];d=JSON.parse(File.read(p));d["packages"]<<d["packages"].last;File.write(p,JSON.generate(d))' "$P/dist/release-manifest.json"; run v1.2.3
[[ "$status" == 64 && ! -s "$ORDER" ]] || fail "extra manifest package accepted"
reset; FAKE_ORIGIN=https://github.com/evil/UpdateBar.git; run v1.2.3; [[ "$status" == 64 && ! -s "$ORDER" ]] || fail "foreign origin accepted"

reset; FAKE_UPLOAD_STATUS=37; run v1.2.3; [[ "$status" == 37 ]] || fail "upload status translated: $status"
reset; FAKE_R2_STATUS=38; run v1.2.3; [[ "$status" == 38 && "$(tail -1 "$ORDER")" == publish-r2 ]] || fail "R2 status/order wrong"
reset; FAKE_EDIT_STATUS=39; run v1.2.3; [[ "$status" == 39 && "$(tail -2 "$ORDER")" == $'publish-r2\npublish-github' ]] || fail "GitHub publication status/order wrong"

# R2 consumes a dedicated immutable three-file snapshot. Replacing live
# dist/updates at publisher invocation cannot split GitHub and R2 bytes.
reset; original_dmg="$(cat "$P/dist/$DMG")"; CONCURRENT_REPLACE=1; run v1.2.3
[[ "$status" == 0 ]] || fail "concurrent live replacement disturbed snapshot publication: $output"
[[ -f "$R2_CAPTURE" && "$(cat "$R2_CAPTURE")" == "$original_dmg" ]] || fail "R2 read replacement bytes instead of the release snapshot"
[[ "$(cat "$A/$DMG")" == "$original_dmg" ]] || fail "GitHub and R2 snapshot bytes diverged"

# Config cannot redirect the fixed repository or host, and secrets never appear in output.
reset; printf "GH_REPO=evil/repo\nGH_HOST=evil.invalid\nR2_SECRET_ACCESS_KEY=secret-sentinel\n" >"$P/.env.release.local"; run v1.2.3
[[ "$status" == 0 && "$output" != *secret-sentinel* ]] || fail "config redirected or leaked: $output"

bash -n "$SOURCE" "$0"; echo "publish-release contract tests passed"
