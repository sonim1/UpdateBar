#!/usr/bin/env bash
set -euo pipefail
set +x
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -eq 1 ]] || { echo 'Usage: Scripts/publish-release.sh v<version>' >&2; exit 64; }
TAG="$1"; [[ "$TAG" =~ ^v[0-9]+([.][0-9]+){1,2}$ ]] || { echo 'Release tag must match v<version>' >&2; exit 64; }
VERSION="${TAG#v}"
CONFIG="${RELEASE_CONFIG_PATH:-$ROOT/.env.release.local}"
if [[ -f "$CONFIG" ]]; then set -a; source "$CONFIG"; set +a; fi
set +x

REPOSITORY='sonim1/UpdateBar'; GH_REPO="$REPOSITORY"; GH_HOST='github.com'; export GH_REPO GH_HOST
GIT_BIN="${GIT_BIN:-git}"; GH_BIN="${GH_BIN:-gh}"; SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
CMP_BIN="${CMP_BIN:-/usr/bin/cmp}"; RUBY_BIN="${RUBY_BIN:-/usr/bin/ruby}"
PUBLISH_UPDATE_SCRIPT="${PUBLISH_UPDATE_SCRIPT:-$ROOT/Scripts/publish-update.sh}"
DIST="$ROOT/dist"; UPDATE_DIR="$DIST/updates"; MANIFEST_NAME=release-manifest.json; APPCAST_NAME=appcast.xml
MAC_NAME="updatebar-$VERSION-macos-arm64.tar.gz"; LINUX_NAME="updatebar-$VERSION-linux-x86_64.tar.gz"; DMG_NAME="UpdateBar-$VERSION-macos-arm64.dmg"

fail(){ echo "$1" >&2; exit "${2:-66}"; }
regular(){ [[ -f "$1" && ! -L "$1" ]] || fail "Required file is missing or unsafe: $1" 66; }
for command_path in "$GIT_BIN" "$GH_BIN" "$SHASUM_BIN" "$CMP_BIN" "$RUBY_BIN"; do
  if [[ "$command_path" == */* ]]; then [[ -x "$command_path" ]] || fail "Required command is unavailable: $command_path" 66
  else command -v "$command_path" >/dev/null 2>&1 || fail "Required command is unavailable: $command_path" 66; fi
done
[[ -x "$PUBLISH_UPDATE_SCRIPT" ]] || fail "Publish-update script is unavailable: $PUBLISH_UPDATE_SCRIPT" 66
[[ -d "$DIST" && ! -L "$DIST" && -d "$UPDATE_DIR" && ! -L "$UPDATE_DIR" ]] || fail 'Release artifact directories are missing or unsafe' 66
regular "$DIST/$MAC_NAME"; regular "$DIST/$MAC_NAME.sha256"
regular "$DIST/$LINUX_NAME"; regular "$DIST/$LINUX_NAME.sha256"
regular "$DIST/$DMG_NAME"; regular "$DIST/$DMG_NAME.sha256"
regular "$UPDATE_DIR/$DMG_NAME"; regular "$UPDATE_DIR/$DMG_NAME.sha256"
regular "$UPDATE_DIR/$APPCAST_NAME"; regular "$DIST/$MANIFEST_NAME"

origin="$($GIT_BIN remote get-url origin)" || { status=$?; echo 'Unable to resolve origin' >&2; exit "$status"; }
case "$origin" in
 "https://github.com/$REPOSITORY"|"https://github.com/$REPOSITORY.git"|"git@github.com:$REPOSITORY.git"|"ssh://git@github.com/$REPOSITORY"|"ssh://git@github.com/$REPOSITORY.git") ;;
 *) fail "Release checkout origin is not $REPOSITORY" 64;;
esac
HEAD_COMMIT="$($GIT_BIN rev-parse HEAD)" || { status=$?; echo 'Unable to resolve HEAD' >&2; exit "$status"; }
[[ "$HEAD_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail 'HEAD is not a lowercase full commit hash' 64
TAG_COMMIT="$($GIT_BIN rev-parse --verify "refs/tags/$TAG^{commit}")" || { status=$?; echo 'Unable to resolve exact release tag' >&2; exit "$status"; }
[[ "$TAG_COMMIT" == "$HEAD_COMMIT" ]] || fail 'Release tag does not point to HEAD' 64

TMP=''; SNAP=''; SNAP_GUARD=''; UPDATE_SNAPSHOT=''
cleanup(){
  local status=$? cleanup_status=0
  trap - EXIT HUP INT TERM
  if [[ -n "$TMP" && -d "$TMP" ]]; then
    [[ -z "$SNAP" || ! -d "$SNAP" || -L "$SNAP" ]] || chmod u+w "$SNAP" 2>/dev/null || :
    [[ -z "$SNAP_GUARD" || ! -d "$SNAP_GUARD" || -L "$SNAP_GUARD" ]] || chmod u+w "$SNAP_GUARD" 2>/dev/null || :
    [[ -z "$UPDATE_SNAPSHOT" || ! -d "$UPDATE_SNAPSHOT" || -L "$UPDATE_SNAPSHOT" ]] || chmod u+w "$UPDATE_SNAPSHOT" 2>/dev/null || :
    rm -rf "$TMP" || cleanup_status=$?
  fi
  [[ "$status" != 0 || "$cleanup_status" == 0 ]] || status="$cleanup_status"
  exit "$status"
}
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
TMP="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-publish-release.XXXXXX")" || exit $?
SNAP="$TMP/assets"; mkdir "$SNAP" || exit $?
asset_names=("$MAC_NAME" "$MAC_NAME.sha256" "$LINUX_NAME" "$LINUX_NAME.sha256" "$DMG_NAME" "$DMG_NAME.sha256" "$APPCAST_NAME" "$MANIFEST_NAME")
original_paths=("$DIST/$MAC_NAME" "$DIST/$MAC_NAME.sha256" "$DIST/$LINUX_NAME" "$DIST/$LINUX_NAME.sha256" "$DIST/$DMG_NAME" "$DIST/$DMG_NAME.sha256" "$UPDATE_DIR/$APPCAST_NAME" "$DIST/$MANIFEST_NAME")

copy_snapshot(){ local source="$1" name="$2"; /bin/cp -p "$source" "$SNAP/$name" || exit $?; regular "$SNAP/$name"; }
copy_snapshot "$DIST/$MAC_NAME" "$MAC_NAME"; copy_snapshot "$DIST/$MAC_NAME.sha256" "$MAC_NAME.sha256"
copy_snapshot "$DIST/$LINUX_NAME" "$LINUX_NAME"; copy_snapshot "$DIST/$LINUX_NAME.sha256" "$LINUX_NAME.sha256"
copy_snapshot "$DIST/$DMG_NAME" "$DMG_NAME"; copy_snapshot "$DIST/$DMG_NAME.sha256" "$DMG_NAME.sha256"
copy_snapshot "$UPDATE_DIR/$APPCAST_NAME" "$APPCAST_NAME"; copy_snapshot "$DIST/$MANIFEST_NAME" "$MANIFEST_NAME"
verify_source_binding(){ local i status; i=0; while [[ "$i" -lt "${#asset_names[@]}" ]]; do if "$CMP_BIN" -s "${original_paths[$i]}" "$SNAP/${asset_names[$i]}"; then :; else status=$?; [[ "$status" == 1 ]] && fail "Release input changed while creating the snapshot: ${asset_names[$i]}" 64; exit "$status"; fi; i=$((i+1)); done; }
verify_source_binding
if "$CMP_BIN" -s "$SNAP/$DMG_NAME" "$UPDATE_DIR/$DMG_NAME"; then :; else status=$?; [[ "$status" == 1 ]] && fail 'GitHub and Sparkle DMG bytes differ' 64; exit "$status"; fi
if "$CMP_BIN" -s "$SNAP/$DMG_NAME.sha256" "$UPDATE_DIR/$DMG_NAME.sha256"; then :; else status=$?; [[ "$status" == 1 ]] && fail 'GitHub and Sparkle DMG checksum bytes differ' 64; exit "$status"; fi

SNAP_GUARD="$TMP/asset-guard"; mkdir "$SNAP_GUARD" || exit $?
for name in "${asset_names[@]}"; do /bin/cp -p "$SNAP/$name" "$SNAP_GUARD/$name" || exit $?; chmod 0444 "$SNAP/$name" "$SNAP_GUARD/$name" || exit $?; done
chmod 0555 "$SNAP" "$SNAP_GUARD" || exit $?
UPDATE_SNAPSHOT="$TMP/update-artifacts"; mkdir "$UPDATE_SNAPSHOT" || exit $?
/bin/cp -p "$SNAP/$DMG_NAME" "$SNAP/$DMG_NAME.sha256" "$SNAP/$APPCAST_NAME" "$UPDATE_SNAPSHOT/" || exit $?
chmod 0444 "$UPDATE_SNAPSHOT/$DMG_NAME" "$UPDATE_SNAPSHOT/$DMG_NAME.sha256" "$UPDATE_SNAPSHOT/$APPCAST_NAME" || exit $?
chmod 0555 "$UPDATE_SNAPSHOT" || exit $?

verify_frozen_asset_snapshot(){
  local name status
  [[ -d "$SNAP" && ! -L "$SNAP" && -d "$SNAP_GUARD" && ! -L "$SNAP_GUARD" ]] || fail 'Frozen release snapshot changed or became unsafe' 64
  if "$RUBY_BIN" -e 'expected=ARGV.drop(2).sort;exit(Dir.children(ARGV[0]).sort==expected && Dir.children(ARGV[1]).sort==expected ? 0 : 64)' "$SNAP" "$SNAP_GUARD" "${asset_names[@]}"; then :; else status=$?; echo 'Frozen release snapshot contains an unexpected file set' >&2; exit "$status"; fi
  for name in "${asset_names[@]}"; do
    [[ -f "$SNAP/$name" && ! -L "$SNAP/$name" && -f "$SNAP_GUARD/$name" && ! -L "$SNAP_GUARD/$name" ]] || fail "Frozen release snapshot entry became unsafe: $name" 64
    if "$CMP_BIN" -s "$SNAP/$name" "$SNAP_GUARD/$name"; then :; else status=$?; [[ "$status" == 1 ]] && fail "Frozen release snapshot changed: $name" 64; exit "$status"; fi
  done
}
verify_frozen_asset_snapshot

sha_file(){ local output status; if output="$($SHASUM_BIN -a 256 "$1")"; then :; else status=$?; echo "SHA-256 failed: $1" >&2; return "$status"; fi; [[ "$output" =~ ^([0-9a-f]{64})[[:space:]] ]] || { echo "Malformed SHA-256 output: $1" >&2; return 66; }; printf '%s' "${BASH_REMATCH[1]}"; }
verify_checksum(){
  local name="$1" line='' count=0 candidate recorded recorded_name actual
  while IFS= read -r candidate || [[ -n "$candidate" ]]; do count=$((count+1)); line="$candidate"; done <"$SNAP/$name.sha256"
  [[ "$count" -eq 1 && "$line" =~ ^([0-9a-f]{64})[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]] || fail "Checksum record is malformed: $name.sha256" 64
  recorded="${BASH_REMATCH[1]}"; recorded_name="${BASH_REMATCH[2]}"; [[ "$recorded_name" == "$name" ]] || fail "Checksum is not bound to $name" 64
  actual="$(sha_file "$SNAP/$name")" || exit $?; [[ "$actual" == "$recorded" ]] || fail "Checksum mismatch: $name" 64
  printf '%s' "$actual"
}
MAC_SHA="$(verify_checksum "$MAC_NAME")"; verify_checksum "$LINUX_NAME" >/dev/null; DMG_SHA="$(verify_checksum "$DMG_NAME")"

if "$RUBY_BIN" -rrexml/document -rbase64 -e '
  path,url,version,length=ARGV
  begin
    raw=File.binread(path); exit 1 if raw.include?("<!DOCTYPE"); doc=REXML::Document.new(raw); ns="http://www.andymatuschak.org/xml-namespaces/sparkle"
    es=[];REXML::XPath.each(doc,"//*[local-name()=\"enclosure\"]"){|e|es<<e};exit 1 unless es.length==1
    e=es[0];a=->(n){x=e.attributes.get_attribute_ns(ns,n);x&&x.value}; sig=a.call("edSignature")
    valid=e.attributes["url"]==url && e.attributes["length"]==length && a.call("shortVersionString")==version && a.call("version")&.match?(/\A[0-9]+(?:\.[0-9]+){0,2}\z/) && sig && Base64.strict_decode64(sig).bytesize==64
    exit(valid ? 0 : 1)
  rescue; exit 1; end
' "$SNAP/$APPCAST_NAME" "https://updates.updatebar.sonim1.com/$DMG_NAME" "$VERSION" "$(stat -f %z "$SNAP/$DMG_NAME")"; then :; else fail 'Appcast is not bound to the release DMG and version' 64; fi

set +e
"$RUBY_BIN" -rjson -e '
  class DuplicateKey < StandardError;end
  class UniqueHash < Hash;def []=(k,v);raise DuplicateKey,k if key?(k);super;end;end
  path,repo,tag,version,commit,mac,mac_sha,dmg,dmg_sha=ARGV
  begin;d=JSON.parse(File.binread(path),object_class:UniqueHash);rescue JSON::ParserError,DuplicateKey,SystemCallError=>e;warn e.message;exit 64;end
  exact=->(v,k){v.is_a?(Hash)&&v.keys.sort==k.sort}; ps=d.is_a?(Hash)&&d["packages"]
  valid=exact.call(d,%w[commit packages repository schemaVersion tag version])&&d["schemaVersion"]==1&&d["repository"]==repo&&d["tag"]==tag&&d["version"]==version&&d["commit"]==commit&&ps.is_a?(Array)&&ps.length==3
  expected=[
    ["formula","updatebar",{"kind"=>"release-asset","name"=>mac,"sha256"=>mac_sha}],
    ["cask","updatebar-app",{"kind"=>"release-asset","name"=>dmg,"sha256"=>dmg_sha}],
    ["formula","updatebar-tui",{"kind"=>"github-tag-archive"}]
  ]
  if valid
    ps.each_with_index do |p,i|
      s=p.is_a?(Hash)&&p["source"]; type,token,want=expected[i]
      valid&&=exact.call(p,%w[source token type])&&p["type"]==type&&p["token"]==token&&exact.call(s,want.keys+(i==2 ? ["sha256"] : []))&&want.all?{|k,v|s[k]==v}&&s["sha256"].is_a?(String)&&s["sha256"].match?(/\A[0-9a-f]{64}\z/)
    end
  end
  exit(valid ? 0 : 64)
' "$SNAP/$MANIFEST_NAME" "$REPOSITORY" "$TAG" "$VERSION" "$HEAD_COMMIT" "$MAC_NAME" "$MAC_SHA" "$DMG_NAME" "$DMG_SHA"
manifest_status=$?; set -e
[[ "$manifest_status" == 0 ]] || { echo 'Release manifest is malformed or does not exactly bind this release' >&2; exit "$manifest_status"; }

verify_update_snapshot(){
  local status
  [[ -d "$UPDATE_SNAPSHOT" && ! -L "$UPDATE_SNAPSHOT" ]] || fail 'Update snapshot directory changed or became unsafe' 64
  if "$RUBY_BIN" -e 'expected=ARGV.drop(1).sort;actual=Dir.children(ARGV[0]).sort;exit(actual==expected ? 0 : 64)' "$UPDATE_SNAPSHOT" "$DMG_NAME" "$DMG_NAME.sha256" "$APPCAST_NAME"; then :; else status=$?; echo 'Update snapshot contains an unexpected file set' >&2; exit "$status"; fi
  for name in "$DMG_NAME" "$DMG_NAME.sha256" "$APPCAST_NAME"; do
    [[ -f "$UPDATE_SNAPSHOT/$name" && ! -L "$UPDATE_SNAPSHOT/$name" ]] || fail "Update snapshot entry changed or became unsafe: $name" 64
    if "$CMP_BIN" -s "$SNAP/$name" "$UPDATE_SNAPSHOT/$name"; then :; else status=$?; [[ "$status" == 1 ]] && fail "Update snapshot changed: $name" 64; exit "$status"; fi
  done
}
verify_update_snapshot

probe=''; set +e; probe="$($GH_BIN api --hostname github.com --include --silent "repos/$REPOSITORY/releases/tags/$TAG" 2>&1)"; probe_status=$?; set -e
http=''; count=0
while IFS= read -r line; do if [[ "$line" =~ ^HTTP/[0-9.]+[[:space:]]+([0-9]{3})([[:space:]]|$) ]]; then count=$((count+1)); http="${BASH_REMATCH[1]}"; fi; done <<<"$probe"
release_state=true
if [[ "$probe_status" == 0 && "$count" == 1 && "$http" == 200 ]]; then
  release_state="$($GH_BIN release view "$TAG" --repo "$REPOSITORY" --json isDraft --jq .isDraft)" || { status=$?; echo 'Unable to inspect GitHub release state' >&2; exit "$status"; }
  [[ "$release_state" == true || "$release_state" == false ]] || fail 'GitHub returned an invalid release state' 66
elif [[ "$probe_status" != 0 && "$count" == 1 && "$http" == 404 ]]; then
  if "$GH_BIN" release create "$TAG" --repo "$REPOSITORY" --draft --verify-tag --generate-notes --title "UpdateBar $VERSION"; then :; else status=$?; echo 'Unable to create GitHub draft release' >&2; exit "$status"; fi
else
  echo 'GitHub release lookup failed' >&2; [[ "$probe_status" != 0 ]] && exit "$probe_status"; exit 66
fi

ASSETS="$($GH_BIN release view "$TAG" --repo "$REPOSITORY" --json assets --jq '.assets[].name')" || { status=$?; echo 'Unable to inspect GitHub release assets' >&2; exit "$status"; }
asset_count(){ local wanted="$1" name total=0; while IFS= read -r name; do [[ "$name" == "$wanted" ]] && total=$((total+1)); done <<<"$ASSETS"; printf '%s' "$total"; }
validate_remote_asset_set(){
  local require_complete="$1" remote_name known name count
  while IFS= read -r remote_name; do
    [[ -n "$remote_name" ]] || continue
    known=0
    for name in "${asset_names[@]}"; do [[ "$remote_name" == "$name" ]] && known=1; done
    [[ "$known" == 1 ]] || fail "GitHub release contains an unexpected asset: $remote_name" 66
  done <<<"$ASSETS"
  for name in "${asset_names[@]}"; do
    count="$(asset_count "$name")"
    [[ "$count" -le 1 ]] || fail "GitHub release asset name is ambiguous: $name" 66
    [[ "$require_complete" != 1 || "$count" == 1 ]] || fail "GitHub release is missing one exact required asset: $name" 66
  done
}
if [[ "$release_state" == false ]]; then validate_remote_asset_set 1; else validate_remote_asset_set 0; fi

prepare_asset(){
  local name="$1" count dir status
  count="$(asset_count "$name")"; [[ "$count" -le 1 ]] || { echo "GitHub release asset name is ambiguous: $name" >&2; return 66; }
  if [[ "$count" == 0 ]]; then
    [[ "$release_state" == true ]] || { echo "Published GitHub release is missing required asset: $name" >&2; return 66; }
    "$GH_BIN" release upload "$TAG" "$SNAP/$name" --repo "$REPOSITORY" || { status=$?; echo "GitHub asset upload failed: $name" >&2; return "$status"; }
    return 0
  fi
  dir="$TMP/download-$name"; mkdir "$dir" || return $?
  "$GH_BIN" release download "$TAG" --repo "$REPOSITORY" --pattern "$name" --dir "$dir" || { status=$?; echo "GitHub asset download failed: $name" >&2; return "$status"; }
  regular "$dir/$name"
  if "$CMP_BIN" -s "$SNAP/$name" "$dir/$name"; then return 0; else status=$?; [[ "$status" == 1 ]] && { echo "GitHub release asset conflict: $name" >&2; return 66; }; return "$status"; fi
}
for name in "${asset_names[@]}"; do prepare_asset "$name" || exit $?; done
ASSETS="$($GH_BIN release view "$TAG" --repo "$REPOSITORY" --json assets --jq '.assets[].name')" || { status=$?; echo 'Unable to re-inspect GitHub release assets' >&2; exit "$status"; }
validate_remote_asset_set 1
verify_frozen_asset_snapshot
verify_update_snapshot
if UPDATE_ARTIFACT_DIR="$UPDATE_SNAPSHOT" "$PUBLISH_UPDATE_SCRIPT"; then :; else status=$?; echo 'R2 update publication failed' >&2; exit "$status"; fi
verify_update_snapshot
verify_frozen_asset_snapshot
if [[ "$release_state" == true ]]; then
  if "$GH_BIN" release edit "$TAG" --repo "$REPOSITORY" --draft=false; then :; else status=$?; echo 'GitHub release publication failed' >&2; exit "$status"; fi
fi
printf 'Published GitHub Release: %s\n' "$TAG"
