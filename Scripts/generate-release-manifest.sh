#!/usr/bin/env bash
set -euo pipefail
set +x
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GIT_BIN="${GIT_BIN:-git}"
CURL_BIN="${CURL_BIN:-curl}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
RUBY_BIN="${RUBY_BIN:-/usr/bin/ruby}"
RENAME_BIN="${RENAME_BIN:-$RUBY_BIN}"
temporary_archive=''; temporary_manifest=''; remote_ref_nonce=''; remote_main_ref=''; remote_tag_ref=''

cleanup() {
  local status=$? cleanup_status=0
  trap - EXIT HUP INT TERM
  if [[ -n "$remote_main_ref" ]]; then "$GIT_BIN" update-ref -d "$remote_main_ref" >/dev/null 2>&1 || cleanup_status=$?; fi
  if [[ -n "$remote_tag_ref" ]]; then "$GIT_BIN" update-ref -d "$remote_tag_ref" >/dev/null 2>&1 || cleanup_status=$?; fi
  [[ -z "$remote_ref_nonce" || ! -d "$remote_ref_nonce" ]] || rm -rf "$remote_ref_nonce" || cleanup_status=$?
  [[ -z "$temporary_archive" ]] || rm -f "$temporary_archive" || cleanup_status=$?
  [[ -z "$temporary_manifest" ]] || rm -f "$temporary_manifest" || cleanup_status=$?
  [[ "$status" != 0 || "$cleanup_status" == 0 ]] || status="$cleanup_status"
  exit "$status"
}
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM

fail() { echo "$1" >&2; exit "${2:-64}"; }
[[ $# -eq 1 ]] || fail 'Usage: Scripts/generate-release-manifest.sh v<version>' 64
tag="$1"
[[ "$tag" =~ ^v[0-9]+([.][0-9]+){1,2}$ ]] || fail 'Tag must match v<version>' 64
version="${tag#v}"

[[ -f version.env && ! -L version.env ]] || fail 'version.env is missing or unsafe' 66
if configured_version="$($RUBY_BIN -e '
  lines=File.binread(ARGV[0]).lines
  match=lines.length==1 && lines[0].match(/\AUPDATEBAR_VERSION=([0-9]+(?:\.[0-9]+){1,2})\n?\z/)
  exit 1 unless match
  print match[1]
' version.env)"; then :; else fail 'version.env must contain exactly one canonical UPDATEBAR_VERSION assignment' 64; fi
[[ "$configured_version" == "$version" ]] || fail 'Tag does not match version.env' 64

origin="$($GIT_BIN remote get-url origin)" || { status=$?; echo 'Unable to resolve origin' >&2; exit "$status"; }
case "$origin" in
  "https://github.com/sonim1/UpdateBar"|"https://github.com/sonim1/UpdateBar.git"|"git@github.com:sonim1/UpdateBar.git"|"ssh://git@github.com/sonim1/UpdateBar"|"ssh://git@github.com/sonim1/UpdateBar.git") ;;
  *) fail 'Release checkout origin is not sonim1/UpdateBar' 64 ;;
esac
dirty="$($GIT_BIN status --porcelain --untracked-files=no)" || { status=$?; echo 'Unable to inspect worktree state' >&2; exit "$status"; }
[[ -z "$dirty" ]] || fail 'Release checkout has tracked changes' 64
head_commit="$($GIT_BIN rev-parse HEAD)" || { status=$?; echo 'Unable to resolve HEAD' >&2; exit "$status"; }
[[ "$head_commit" =~ ^[0-9a-f]{40}$ ]] || fail 'HEAD is not a lowercase full commit hash' 64
tag_commit="$($GIT_BIN rev-parse --verify "refs/tags/$tag^{commit}")" || { status=$?; echo 'Unable to resolve exact release tag' >&2; exit "$status"; }
[[ "$tag_commit" =~ ^[0-9a-f]{40}$ && "$tag_commit" == "$head_commit" ]] || fail 'Release tag does not point to HEAD' 64
remote_ref_nonce="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-tag-ref.XXXXXX")" || exit $?
remote_main_ref="refs/updatebar-release-verification/${remote_ref_nonce##*/}-main"
remote_tag_ref="refs/updatebar-release-verification/${remote_ref_nonce##*/}"
if "$GIT_BIN" fetch --quiet --no-tags origin "refs/heads/main:$remote_main_ref"; then :; else status=$?; echo 'Unable to fetch exact remote main branch' >&2; exit "$status"; fi
main_commit="$($GIT_BIN rev-parse --verify "$remote_main_ref^{commit}")" || { status=$?; echo 'Unable to peel fetched remote main branch' >&2; exit "$status"; }
[[ "$main_commit" =~ ^[0-9a-f]{40}$ ]] || fail 'Fetched remote main commit is not canonical' 64
if "$GIT_BIN" merge-base --is-ancestor "$head_commit" "$main_commit"; then :; else status=$?; [[ "$status" == 1 ]] && fail 'Release commit is not an ancestor of freshly fetched remote main' 64; echo 'Unable to compare release commit with fetched remote main' >&2; exit "$status"; fi
if "$GIT_BIN" fetch --quiet --no-tags origin "refs/tags/$tag:$remote_tag_ref"; then :; else status=$?; echo 'Unable to fetch exact remote release tag' >&2; exit "$status"; fi
remote_tag_commit="$($GIT_BIN rev-parse --verify "$remote_tag_ref^{commit}")" || { status=$?; echo 'Unable to peel fetched remote release tag' >&2; exit "$status"; }
[[ "$remote_tag_commit" =~ ^[0-9a-f]{40}$ && "$remote_tag_commit" == "$tag_commit" && "$remote_tag_commit" == "$head_commit" ]] || fail 'Remote release tag does not match local tag and HEAD' 64
if "$GIT_BIN" update-ref -d "$remote_main_ref"; then remote_main_ref=''; else status=$?; echo 'Unable to clean isolated remote main ref' >&2; exit "$status"; fi
if "$GIT_BIN" update-ref -d "$remote_tag_ref"; then remote_tag_ref=''; else status=$?; echo 'Unable to clean isolated remote tag ref' >&2; exit "$status"; fi
rm -rf "$remote_ref_nonce"; remote_ref_nonce=''

dist="$ROOT/dist"
[[ -d "$dist" && ! -L "$dist" ]] || fail 'dist is missing or unsafe' 66
mac_name="updatebar-$version-macos-arm64.tar.gz"
linux_name="updatebar-$version-linux-x86_64.tar.gz"
dmg_name="UpdateBar-$version-macos-arm64.dmg"
for name in "$mac_name" "$mac_name.sha256" "$linux_name" "$linux_name.sha256" "$dmg_name" "$dmg_name.sha256"; do
  [[ -f "$dist/$name" && ! -L "$dist/$name" ]] || fail "Missing or unsafe release artifact: $name" 66
done

if "$RUBY_BIN" -e '
  directory,version,*allowed=ARGV
  pattern=/\A(?:updatebar|UpdateBar)-#{Regexp.escape(version)}-.*(?:\.tar\.gz|\.dmg)(?:\.sha256)?\z/
  unexpected=Dir.children(directory).find{|name|pattern.match?(name)&&!allowed.include?(name)}
  if unexpected
    warn "Unexpected release artifact candidate: #{unexpected.inspect}"
    exit 64
  end
' "$dist" "$version" "$mac_name" "$mac_name.sha256" "$linux_name" "$linux_name.sha256" "$dmg_name" "$dmg_name.sha256"; then :; else exit $?; fi

sha_file() {
  local path="$1" output status
  if output="$($SHASUM_BIN -a 256 "$path")"; then :; else status=$?; echo "Unable to checksum ${path##*/}" >&2; return "$status"; fi
  [[ "$output" =~ ^([0-9a-f]{64})[[:space:]]+.+$ ]] || { echo "Malformed checksum output for ${path##*/}" >&2; return 66; }
  printf '%s' "${BASH_REMATCH[1]}"
}

verify_checksum() {
  local name="$1" checksum="$dist/$1.sha256" line='' count=0 recorded recorded_name computed
  while IFS= read -r candidate || [[ -n "$candidate" ]]; do count=$((count+1)); line="$candidate"; done <"$checksum"
  [[ "$count" -eq 1 && "$line" =~ ^([0-9a-f]{64})[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]] || { echo "Malformed checksum record: ${checksum##*/}" >&2; return 1; }
  recorded="${BASH_REMATCH[1]}"; recorded_name="${BASH_REMATCH[2]}"
  [[ "$recorded_name" == "$name" ]] || { echo "Checksum is not bound to $name" >&2; return 1; }
  computed="$(sha_file "$dist/$name")" || return $?
  [[ "$computed" == "$recorded" ]] || { echo "Checksum mismatch: $name" >&2; return 1; }
  printf '%s' "$computed"
}

mac_sha="$(verify_checksum "$mac_name")" || exit $?
linux_sha="$(verify_checksum "$linux_name")" || exit $?
dmg_sha="$(verify_checksum "$dmg_name")" || exit $?

temporary_archive="$(mktemp "${TMPDIR:-/tmp}/updatebar-tag-archive.XXXXXX")" || exit $?
chmod 600 "$temporary_archive" || exit $?
tag_archive_url="https://github.com/sonim1/UpdateBar/archive/refs/tags/$tag.tar.gz"
if "$CURL_BIN" --fail --location --silent --show-error --output "$temporary_archive" "$tag_archive_url"; then :; else status=$?; echo 'Unable to download fixed GitHub tag archive' >&2; exit "$status"; fi
[[ -f "$temporary_archive" && ! -L "$temporary_archive" ]] || fail 'Downloaded tag archive is unsafe' 66
tui_sha="$(sha_file "$temporary_archive")" || exit $?

manifest="$dist/release-manifest.json"
[[ ! -L "$manifest" && ( ! -e "$manifest" || -f "$manifest" ) ]] || fail 'Release manifest destination is unsafe' 66
temporary_manifest="$(mktemp "$dist/.release-manifest.XXXXXX")" || exit $?
chmod 600 "$temporary_manifest" || exit $?
if "$RUBY_BIN" -rjson -e '
  path,tag,version,commit,mac_name,mac_sha,dmg_name,dmg_sha,tui_sha=ARGV
  data={schemaVersion:1,repository:"sonim1/UpdateBar",tag:tag,version:version,commit:commit,packages:[
    {type:"formula",token:"updatebar",source:{kind:"release-asset",name:mac_name,sha256:mac_sha}},
    {type:"cask",token:"updatebar-app",source:{kind:"release-asset",name:dmg_name,sha256:dmg_sha}},
    {type:"formula",token:"updatebar-tui",source:{kind:"github-tag-archive",sha256:tui_sha}}
  ]}
  File.binwrite(path,JSON.pretty_generate(data)+"\n")
' "$temporary_manifest" "$tag" "$version" "$head_commit" "$mac_name" "$mac_sha" "$dmg_name" "$dmg_sha" "$tui_sha"; then :; else exit $?; fi

# Revalidate every local release input after rendering so path/content substitution
# cannot leave a successful manifest bound to bytes that are no longer present.
current_sha="$(verify_checksum "$mac_name")" || exit $?
[[ "$current_sha" == "$mac_sha" ]] || fail "Release input changed during generation: $mac_name" 64
current_sha="$(verify_checksum "$linux_name")" || exit $?
[[ "$current_sha" == "$linux_sha" ]] || fail "Release input changed during generation: $linux_name" 64
current_sha="$(verify_checksum "$dmg_name")" || exit $?
[[ "$current_sha" == "$dmg_sha" ]] || fail "Release input changed during generation: $dmg_name" 64

if "$RENAME_BIN" -e '
  source,destination=ARGV
  begin
    stat=File.lstat(destination)
    abort "Release manifest destination is unsafe" unless stat.file? && !stat.symlink?
  rescue Errno::ENOENT
  end
  File.rename(source,destination)
' "$temporary_manifest" "$manifest"; then :; else status=$?; echo 'Unable to finalize release manifest' >&2; exit "$status"; fi
temporary_manifest=''
printf '%s\n' "$manifest"
