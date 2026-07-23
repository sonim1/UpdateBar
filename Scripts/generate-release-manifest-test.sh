#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Scripts/generate-release-manifest.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
[[ -x "$SOURCE" ]] || fail "generate-release-manifest.sh is missing or not executable"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-manifest-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
P="$TMP/project"; B="$TMP/bin"; LOG="$TMP/curl.log"
mkdir -p "$P/Scripts" "$P/dist" "$B"
cp "$SOURCE" "$P/Scripts/generate-release-manifest.sh"
chmod +x "$P/Scripts/generate-release-manifest.sh"

COMMIT=0123456789abcdef0123456789abcdef01234567
VERSION=1.2.3
TAG=v1.2.3
MAC="updatebar-$VERSION-macos-arm64.tar.gz"
LINUX="updatebar-$VERSION-linux-x86_64.tar.gz"
DMG="UpdateBar-$VERSION-macos-arm64.dmg"

cat >"$B/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$GIT_LOG"
case "$*" in
  'remote get-url origin') printf '%s\n' "${FAKE_ORIGIN:-git@github.com:sonim1/UpdateBar.git}" ;;
  'status --porcelain --untracked-files=no') printf '%s' "${FAKE_DIRTY:-}" ;;
  'rev-parse HEAD') printf '%s\n' "${FAKE_HEAD:-0123456789abcdef0123456789abcdef01234567}" ;;
  'rev-parse --verify refs/tags/v1.2.3^{commit}') printf '%s\n' "${FAKE_TAG_COMMIT:-0123456789abcdef0123456789abcdef01234567}" ;;
  fetch\ --quiet\ --no-tags\ origin\ refs/heads/main:refs/updatebar-release-verification/*-main) exit "${FAKE_FETCH_STATUS:-0}" ;;
  rev-parse\ --verify\ refs/updatebar-release-verification/*-main'^{commit}') printf '%s\n' "${FAKE_MAIN:-0123456789abcdef0123456789abcdef01234567}" ;;
  fetch\ --quiet\ --no-tags\ origin\ refs/tags/v1.2.3:refs/updatebar-release-verification/*) exit "${FAKE_REMOTE_TAG_FETCH_STATUS:-0}" ;;
  rev-parse\ --verify\ refs/updatebar-release-verification/*'^{commit}') printf '%s\n' "${FAKE_REMOTE_TAG_COMMIT:-0123456789abcdef0123456789abcdef01234567}" ;;
  update-ref\ -d\ refs/updatebar-release-verification/*) exit "${FAKE_REF_CLEANUP_STATUS:-0}" ;;
  *) exit 91 ;;
esac
EOF
cat >"$B/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CURL_LOG"
[[ "$*" == '--fail --location --silent --show-error --output '*' https://github.com/sonim1/UpdateBar/archive/refs/tags/v1.2.3.tar.gz' ]] || exit 92
out=''
while [[ $# -gt 0 ]]; do case "$1" in --output) out="$2"; shift 2;; *) shift;; esac; done
[[ -n "$out" ]] || exit 93
printf 'fixed tag archive bytes\n' >"$out"
exit "${FAKE_CURL_STATUS:-0}"
EOF
cat >"$B/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == -a && "$2" == 256 && $# == 3 ]] || exit 94
output="$(/usr/bin/shasum "$@")"
printf '%s\n' "$output"
if [[ -n "${FAKE_SUBSTITUTE_SOURCE:-}" && "${3##*/}" == updatebar-1.2.3-macos-arm64.tar.gz && ! -e "$FAKE_SUBSTITUTE_MARKER" ]]; then
  : >"$FAKE_SUBSTITUTE_MARKER"
  rm "$3"
  ln -s /etc/hosts "$3"
fi
EOF
chmod +x "$B"/*

write_checksum() {
  local path="$1" name hash
  name="$(basename "$path")"; hash="$(/usr/bin/shasum -a 256 "$path" | awk '{print $1}')"
  printf '%s  %s\n' "$hash" "$name" >"$path.sha256"
}

reset_fixture() {
  rm -rf "$P/dist"; mkdir -p "$P/dist"; : >"$LOG"; : >"$TMP/git.log"
  printf 'UPDATEBAR_VERSION=%s\n' "$VERSION" >"$P/version.env"
  printf 'mac cli\n' >"$P/dist/$MAC"; write_checksum "$P/dist/$MAC"
  printf 'linux cli\n' >"$P/dist/$LINUX"; write_checksum "$P/dist/$LINUX"
  printf 'dmg\n' >"$P/dist/$DMG"; write_checksum "$P/dist/$DMG"
  FAKE_ORIGIN='git@github.com:sonim1/UpdateBar.git'; FAKE_DIRTY=''; FAKE_HEAD="$COMMIT"
  FAKE_TAG_COMMIT="$COMMIT"; FAKE_MAIN="$COMMIT"; FAKE_FETCH_STATUS=0; FAKE_CURL_STATUS=0
  FAKE_REMOTE_TAG_COMMIT="$COMMIT"; FAKE_REMOTE_TAG_FETCH_STATUS=0; FAKE_REF_CLEANUP_STATUS=0
  FAKE_SUBSTITUTE_SOURCE=''; rm -f "$TMP/substituted"
}

run_generator() {
  set +e
  output="$(GIT_BIN="$B/git" CURL_BIN="$B/curl" SHASUM_BIN="$B/shasum" RENAME_BIN=/usr/bin/ruby \
    GIT_LOG="$TMP/git.log" CURL_LOG="$LOG" FAKE_ORIGIN="$FAKE_ORIGIN" FAKE_DIRTY="$FAKE_DIRTY" \
    FAKE_HEAD="$FAKE_HEAD" FAKE_TAG_COMMIT="$FAKE_TAG_COMMIT" FAKE_MAIN="$FAKE_MAIN" \
    FAKE_FETCH_STATUS="$FAKE_FETCH_STATUS" FAKE_CURL_STATUS="$FAKE_CURL_STATUS" \
    FAKE_REMOTE_TAG_COMMIT="$FAKE_REMOTE_TAG_COMMIT" FAKE_REMOTE_TAG_FETCH_STATUS="$FAKE_REMOTE_TAG_FETCH_STATUS" FAKE_REF_CLEANUP_STATUS="$FAKE_REF_CLEANUP_STATUS" \
    FAKE_SUBSTITUTE_SOURCE="$FAKE_SUBSTITUTE_SOURCE" FAKE_SUBSTITUTE_MARKER="$TMP/substituted" \
    "$P/Scripts/generate-release-manifest.sh" "$@" 2>&1)"
  status=$?
  set -e
}

reset_fixture; run_generator "$TAG"
[[ "$status" == 0 ]] || fail "valid generation failed ($status): $output"
MANIFEST="$P/dist/release-manifest.json"; [[ -f "$MANIFEST" && ! -L "$MANIFEST" ]] || fail "manifest absent"
MAC_SHA="$(/usr/bin/shasum -a 256 "$P/dist/$MAC" | awk '{print $1}')"
DMG_SHA="$(/usr/bin/shasum -a 256 "$P/dist/$DMG" | awk '{print $1}')"
TUI_SHA="$(printf 'fixed tag archive bytes\n' | /usr/bin/shasum -a 256 | awk '{print $1}')"
EXPECTED_COMMIT="$COMMIT" EXPECTED_MAC="$MAC_SHA" EXPECTED_DMG="$DMG_SHA" EXPECTED_TUI="$TUI_SHA" /usr/bin/ruby -rjson -e '
  a=JSON.parse(File.read(ARGV[0])); e={"schemaVersion"=>1,"repository"=>"sonim1/UpdateBar","tag"=>"v1.2.3","version"=>"1.2.3","commit"=>ENV.fetch("EXPECTED_COMMIT"),"packages"=>[
    {"type"=>"formula","token"=>"updatebar","source"=>{"kind"=>"release-asset","name"=>"updatebar-1.2.3-macos-arm64.tar.gz","sha256"=>ENV.fetch("EXPECTED_MAC")}},
    {"type"=>"cask","token"=>"updatebar-app","source"=>{"kind"=>"release-asset","name"=>"UpdateBar-1.2.3-macos-arm64.dmg","sha256"=>ENV.fetch("EXPECTED_DMG")}},
    {"type"=>"formula","token"=>"updatebar-tui","source"=>{"kind"=>"github-tag-archive","sha256"=>ENV.fetch("EXPECTED_TUI")}}
  ]}; abort "manifest mismatch" unless a==e; abort "missing newline" unless File.binread(ARGV[0]).end_with?("\n")
' "$MANIFEST"
grep -q '^fetch --quiet --no-tags origin refs/heads/main:refs/updatebar-release-verification/.*-main$' "$TMP/git.log" || fail "remote main was not fetched into an isolated ref"
[[ "$(grep -c '^update-ref -d refs/updatebar-release-verification/' "$TMP/git.log")" -eq 2 ]] || fail "isolated main/tag refs were not both cleaned after success"
grep -Fq 'https://github.com/sonim1/UpdateBar/archive/refs/tags/v1.2.3.tar.gz' "$LOG" || fail "tag archive URL was not fixed"

failure() {
  local label="$1" expected="$2"; shift 2
  reset_fixture; "$@"; run_generator "$TAG"
  [[ "$status" == "$expected" ]] || fail "$label returned $status, expected $expected: $output"
  [[ ! -e "$P/dist/release-manifest.json" ]] || fail "$label wrote a manifest"
}
noop() { :; }
bad_version() { printf 'UPDATEBAR_VERSION=1.2.4\n' >"$P/version.env"; }
duplicate_version() { printf 'UPDATEBAR_VERSION=1.2.3\nUPDATEBAR_VERSION=1.2.3\n' >"$P/version.env"; }
dirty() { FAKE_DIRTY=' M Sources/x.swift'; }
wrong_origin() { FAKE_ORIGIN='https://github.com/attacker/UpdateBar.git'; }
wrong_tag() { FAKE_TAG_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; }
wrong_main() { FAKE_MAIN=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; }
wrong_remote_tag() { FAKE_REMOTE_TAG_COMMIT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; }
missing_remote_tag() { FAKE_REMOTE_TAG_FETCH_STATUS=42; }
bad_commit() { FAKE_HEAD=ABCDEF; FAKE_TAG_COMMIT=ABCDEF; FAKE_MAIN=ABCDEF; }
missing_mac() { rm "$P/dist/$MAC"; }
missing_linux() { rm "$P/dist/$LINUX"; }
bad_mac_checksum() { printf '%064d  %s\n' 0 "$MAC" >"$P/dist/$MAC.sha256"; }
bad_linux_checksum() { printf '%064d  %s\n' 0 "$LINUX" >"$P/dist/$LINUX.sha256"; }
wrong_platform() { mv "$P/dist/$MAC" "$P/dist/updatebar-$VERSION-macos-x86_64.tar.gz"; mv "$P/dist/$MAC.sha256" "$P/dist/updatebar-$VERSION-macos-x86_64.tar.gz.sha256"; }
extra_candidate() { printf x >"$P/dist/updatebar-$VERSION-linux-arm64.tar.gz"; }
unsafe_symlink() { rm "$P/dist/$DMG"; ln -s /etc/hosts "$P/dist/$DMG"; }
source_substitution() { FAKE_SUBSTITUTE_SOURCE=1; }

failure bad-version 64 bad_version
failure duplicate-version 64 duplicate_version
failure dirty 64 dirty
failure wrong-origin 64 wrong_origin
failure wrong-tag 64 wrong_tag
failure wrong-main 64 wrong_main
failure wrong-remote-tag 64 wrong_remote_tag
failure missing-remote-tag 42 missing_remote_tag
failure bad-commit 64 bad_commit
failure missing-mac 66 missing_mac
failure missing-linux 66 missing_linux
failure bad-checksum 1 bad_mac_checksum
failure bad-linux-checksum 1 bad_linux_checksum
failure wrong-platform 66 wrong_platform
failure extra-candidate 64 extra_candidate
failure unsafe-symlink 66 unsafe_symlink
failure source-substitution 1 source_substitution

reset_fixture; FAKE_FETCH_STATUS=37; run_generator "$TAG"; [[ "$status" == 37 ]] || fail "fetch status was translated: $status"
reset_fixture; FAKE_CURL_STATUS=38; run_generator "$TAG"; [[ "$status" == 38 ]] || fail "curl status was translated: $status"

# Exact-path finalization must preserve substituted destinations and propagate rename errors.
reset_fixture; mkdir "$P/dist/release-manifest.json"; printf keep >"$P/dist/release-manifest.json/sentinel"; run_generator "$TAG"
[[ "$status" != 0 && -f "$P/dist/release-manifest.json/sentinel" ]] || fail "unsafe destination was changed"
reset_fixture; printf old >"$P/dist/release-manifest.json"; RENAME_BIN="$B/rename-fail"
cat >"$B/rename-fail" <<'EOF'
#!/usr/bin/env bash
exit 39
EOF
chmod +x "$B/rename-fail"
set +e; output="$(GIT_BIN="$B/git" CURL_BIN="$B/curl" SHASUM_BIN="$B/shasum" RENAME_BIN="$B/rename-fail" GIT_LOG="$TMP/git.log" CURL_LOG="$LOG" FAKE_ORIGIN="$FAKE_ORIGIN" FAKE_DIRTY='' FAKE_HEAD="$COMMIT" FAKE_TAG_COMMIT="$COMMIT" FAKE_MAIN="$COMMIT" FAKE_FETCH_STATUS=0 FAKE_CURL_STATUS=0 FAKE_SUBSTITUTE_SOURCE='' FAKE_SUBSTITUTE_MARKER="$TMP/substituted" "$P/Scripts/generate-release-manifest.sh" "$TAG" 2>&1)"; status=$?; set -e
[[ "$status" == 39 && "$(cat "$P/dist/release-manifest.json")" == old ]] || fail "rename failure was not transactional"

reset_fixture
cat >"$B/rename-swap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination="${!#}"
mkdir "$destination"
printf keep >"$destination/sentinel"
exec /usr/bin/ruby "$@"
EOF
chmod +x "$B/rename-swap"
set +e; output="$(GIT_BIN="$B/git" CURL_BIN="$B/curl" SHASUM_BIN="$B/shasum" RENAME_BIN="$B/rename-swap" GIT_LOG="$TMP/git.log" CURL_LOG="$LOG" FAKE_ORIGIN="$FAKE_ORIGIN" FAKE_DIRTY='' FAKE_HEAD="$COMMIT" FAKE_TAG_COMMIT="$COMMIT" FAKE_MAIN="$COMMIT" FAKE_FETCH_STATUS=0 FAKE_CURL_STATUS=0 FAKE_SUBSTITUTE_SOURCE='' FAKE_SUBSTITUTE_MARKER="$TMP/substituted" "$P/Scripts/generate-release-manifest.sh" "$TAG" 2>&1)"; status=$?; set -e
[[ "$status" != 0 && -f "$P/dist/release-manifest.json/sentinel" ]] || fail "destination substitution was not rejected safely"

# Real Git proves an exact remote tag is fetched independently of a moved
# local tag, and that a same-named branch cannot satisfy the tag refspec.
REAL_REMOTE="$TMP/real-remote.git"; REAL_PROJECT="$TMP/real-project"; REAL_GIT="$TMP/real-git"
/usr/bin/git init --bare "$REAL_REMOTE" >/dev/null
/usr/bin/git init -b main "$REAL_PROJECT" >/dev/null
/usr/bin/git -C "$REAL_PROJECT" config user.email test@example.invalid
/usr/bin/git -C "$REAL_PROJECT" config user.name Test
printf one >"$REAL_PROJECT/tracked"; /usr/bin/git -C "$REAL_PROJECT" add tracked; /usr/bin/git -C "$REAL_PROJECT" commit -m one >/dev/null
/usr/bin/git -C "$REAL_PROJECT" remote add origin "$REAL_REMOTE"; /usr/bin/git -C "$REAL_PROJECT" tag v1.2.3
/usr/bin/git -C "$REAL_PROJECT" push origin main refs/tags/v1.2.3 >/dev/null
printf two >"$REAL_PROJECT/tracked"; /usr/bin/git -C "$REAL_PROJECT" commit -am two >/dev/null; /usr/bin/git -C "$REAL_PROJECT" push origin main >/dev/null
/usr/bin/git -C "$REAL_PROJECT" tag -f v1.2.3 >/dev/null
mkdir -p "$REAL_PROJECT/Scripts" "$REAL_PROJECT/dist"; cp "$SOURCE" "$REAL_PROJECT/Scripts/generate-release-manifest.sh"; chmod +x "$REAL_PROJECT/Scripts/generate-release-manifest.sh"
printf 'UPDATEBAR_VERSION=1.2.3\n' >"$REAL_PROJECT/version.env"
for n in "$MAC" "$LINUX" "$DMG"; do printf '%s\n' "$n" >"$REAL_PROJECT/dist/$n"; (cd "$REAL_PROJECT/dist" && /usr/bin/shasum -a 256 "$n" >"$n.sha256"); done
cat >"$REAL_GIT" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == 'remote get-url origin' ]]; then echo git@github.com:sonim1/UpdateBar.git; exit 0; fi
exec /usr/bin/git "$@"
EOF
chmod +x "$REAL_GIT"
set +e; output="$(cd "$REAL_PROJECT" && GIT_BIN="$REAL_GIT" CURL_BIN="$B/curl" SHASUM_BIN=/usr/bin/shasum CURL_LOG="$LOG" Scripts/generate-release-manifest.sh v1.2.3 2>&1)"; status=$?; set -e
[[ "$status" == 64 ]] || fail "real stale remote tag was accepted: $status $output"
[[ -z "$(/usr/bin/git -C "$REAL_PROJECT" for-each-ref refs/updatebar-release-verification)" ]] || fail "real isolated tag ref leaked after mismatch"
/usr/bin/git -C "$REAL_PROJECT" push origin :refs/tags/v1.2.3 >/dev/null
/usr/bin/git -C "$REAL_PROJECT" push origin HEAD:refs/heads/v1.2.3 >/dev/null
set +e; output="$(cd "$REAL_PROJECT" && GIT_BIN="$REAL_GIT" CURL_BIN="$B/curl" SHASUM_BIN=/usr/bin/shasum CURL_LOG="$LOG" Scripts/generate-release-manifest.sh v1.2.3 2>&1)"; status=$?; set -e
[[ "$status" != 0 ]] || fail "same-named remote branch satisfied exact tag fetch"
[[ -z "$(/usr/bin/git -C "$REAL_PROJECT" for-each-ref refs/updatebar-release-verification)" ]] || fail "real isolated tag ref leaked after missing tag"
/usr/bin/git -C "$REAL_PROJECT" push origin :refs/heads/v1.2.3 >/dev/null
REAL_OLD_HEAD="$(/usr/bin/git -C "$REAL_PROJECT" rev-parse HEAD)"
/usr/bin/git -C "$REAL_PROJECT" push origin refs/tags/v1.2.3 >/dev/null
printf three >"$REAL_PROJECT/tracked"; /usr/bin/git -C "$REAL_PROJECT" commit -am three >/dev/null; REAL_REMOTE_MAIN="$(/usr/bin/git -C "$REAL_PROJECT" rev-parse HEAD)"; /usr/bin/git -C "$REAL_PROJECT" push origin main >/dev/null
/usr/bin/git -C "$REAL_PROJECT" reset --hard "$REAL_OLD_HEAD" >/dev/null
/usr/bin/git -C "$REAL_PROJECT" update-ref refs/remotes/origin/main "$REAL_OLD_HEAD"
/usr/bin/git -C "$REAL_PROJECT" config --unset-all remote.origin.fetch || :
/usr/bin/git -C "$REAL_PROJECT" config --add remote.origin.fetch '+refs/heads/not-main:refs/remotes/origin/not-main'
set +e; output="$(cd "$REAL_PROJECT" && GIT_BIN="$REAL_GIT" CURL_BIN="$B/curl" SHASUM_BIN=/usr/bin/shasum CURL_LOG="$LOG" Scripts/generate-release-manifest.sh v1.2.3 2>&1)"; status=$?; set -e
[[ "$status" == 64 ]] || fail "stale refs/remotes/origin/main bypassed exact remote main: $status $output"
[[ -z "$(/usr/bin/git -C "$REAL_PROJECT" for-each-ref refs/updatebar-release-verification)" ]] || fail "isolated main/tag refs leaked after main mismatch"
/usr/bin/git -C "$REAL_PROJECT" reset --hard "$REAL_REMOTE_MAIN" >/dev/null; /usr/bin/git -C "$REAL_PROJECT" tag -f v1.2.3 >/dev/null; /usr/bin/git -C "$REAL_PROJECT" push --force origin refs/tags/v1.2.3 >/dev/null
set +e; output="$(cd "$REAL_PROJECT" && GIT_BIN="$REAL_GIT" CURL_BIN="$B/curl" SHASUM_BIN=/usr/bin/shasum CURL_LOG="$LOG" Scripts/generate-release-manifest.sh v1.2.3 2>&1)"; status=$?; set -e
[[ "$status" == 0 ]] || fail "matching isolated remote main/tag provenance failed: $status $output"
[[ -z "$(/usr/bin/git -C "$REAL_PROJECT" for-each-ref refs/updatebar-release-verification)" ]] || fail "isolated refs leaked after success"

bash -n "$SOURCE" "$0"
echo "generate-release-manifest contract tests passed"
