#!/usr/bin/env bash
set -euo pipefail
set +x
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 0 ]] || { echo "Usage: Scripts/publish-update.sh" >&2; exit 64; }
DIR="${UPDATE_ARTIFACT_DIR:-$ROOT/dist/updates}"
BUCKET="${R2_BUCKET_NAME:-updatebar-updates}"
DOMAIN="${UPDATE_DOMAIN:-updates.updatebar.sonim1.com}"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
ACCESS="${R2_ACCESS_KEY_ID:-}"; SECRET="${R2_SECRET_ACCESS_KEY:-}"
unset R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY AUTH
export -n ACCESS SECRET 2>/dev/null || :
CURL_BIN="${CURL_BIN:-/usr/bin/curl}"; SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"; CMP_BIN="${CMP_BIN:-/usr/bin/cmp}"
[[ "$BUCKET" == updatebar-updates && "$DOMAIN" == updates.updatebar.sonim1.com ]] || { echo "Update hosting contract is fixed" >&2; exit 64; }
[[ "$ACCOUNT_ID" =~ ^[A-Fa-f0-9]{32}$ && "$ACCESS" =~ ^[A-Za-z0-9]+$ && -n "$SECRET" && ! "$SECRET" =~ [[:cntrl:]] ]] || { echo "Valid R2 credentials and a 32-character hexadecimal CLOUDFLARE_ACCOUNT_ID are required" >&2; exit 64; }

fail() { echo "$1" >&2; exit "${2:-1}"; }
regular() { [[ -f "$1" && ! -L "$1" ]] || fail "Missing or unsafe $2: $1" 66; }
escape() { local v="$1"; v="${v//\\/\\\\}"; v="${v//\"/\\\"}"; printf '%s' "$v"; }
AUTH="user = \"$(escape "$ACCESS"):$(escape "$SECRET")\""; export -n AUTH 2>/dev/null || :; ACCESS=''; SECRET=''
ORIGIN="https://$ACCOUNT_ID.r2.cloudflarestorage.com/$BUCKET/"; PUBLIC="https://$DOMAIN/"
APPCAST="$DIR/appcast.xml"; regular "$APPCAST" appcast
TMP="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-publish.XXXXXX")"
cleanup() { status=$?; trap - EXIT HUP INT TERM; [[ ! -d "$TMP" ]] || rm -rf "$TMP"; exit "$status"; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
entry_count=0
entries="$TMP/artifact-entries"
if find "$DIR" -mindepth 1 -maxdepth 1 -print0 >"$entries"; then :; else status=$?; echo "Unable to enumerate update artifacts" >&2; exit "$status"; fi
while IFS= read -r -d '' entry; do
  [[ -f "$entry" && ! -L "$entry" ]] || fail "Update artifact directory contains an unsafe entry: $entry"
  entry_count=$((entry_count+1))
done <"$entries"
[[ "$entry_count" == 3 ]] || fail "Update artifact directory must contain exactly appcast.xml, one DMG, and its checksum"

appcast_metadata() {
  ruby -rrexml/document -rbase64 -e '
    begin
      raw=File.binread(ARGV[0]); abort if raw.include?("<!DOCTYPE"); d=REXML::Document.new(raw); ns="http://www.andymatuschak.org/xml-namespaces/sparkle"
      abort unless d.root && d.root.name=="rss" && d.root.namespaces["sparkle"]==ns
      items=[]; REXML::XPath.each(d,"//*[local-name()=\"item\"]"){|e|items<<e}; abort unless items.length==1
      es=[]; REXML::XPath.each(d,"//*[local-name()=\"enclosure\"]"){|e|es<<e}; abort unless es.length==1 && es[0].parent==items[0]
      e=es[0]; a=->(n){x=e.attributes.get_attribute_ns(ns,n); x&&x.value}
      v=[e.attributes["url"],e.attributes["length"],a.call("version"),a.call("shortVersionString"),a.call("edSignature")]
      abort if v.any?{|x|x.nil?||x.include?("\t")||x.include?("\n")}; abort unless Base64.strict_decode64(v[4]).bytesize==64; puts v.join("\t")
    rescue; exit 1; end
  ' "$1"
}
metadata="$(appcast_metadata "$APPCAST")" || fail "Appcast is malformed or unsigned"
IFS=$'\t' read -r enclosure length build version signature <<<"$metadata"
[[ "$version" =~ ^[0-9]+([.][0-9]+){1,2}$ && "$build" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || fail "Appcast version metadata is invalid"
prefix="${PUBLIC}UpdateBar-"; case "$enclosure" in "$prefix"*'-macos-arm64.dmg') ;; *) fail "Appcast enclosure URL is not canonical";; esac
NAME="${enclosure#"$PUBLIC"}"; [[ "$NAME" == "UpdateBar-${version}-macos-arm64.dmg" && "$NAME" != */* ]] || fail "Appcast artifact name/version mismatch"
DMG="$DIR/$NAME"; CHECKSUM="$DMG.sha256"; regular "$DMG" DMG; regular "$CHECKSUM" checksum
[[ "$length" == "$(stat -f %z "$DMG")" ]] || fail "Appcast enclosure length mismatch"
read -r recorded recorded_name extra <"$CHECKSUM" || fail "Unable to read checksum"
[[ -z "${extra:-}" && "$recorded" =~ ^[0-9a-f]{64}$ && "$recorded_name" == "$NAME" && "$(wc -l <"$CHECKSUM"|tr -d ' ')" == 1 ]] || fail "Checksum record is malformed or unbound"
sha() { local o; o="$("$SHASUM_BIN" -a 256 "$1")" || return $?; [[ "$o" =~ ^([0-9a-f]{64})[[:space:]] ]] || return 66; printf '%s' "${BASH_REMATCH[1]}"; }
LOCAL_HASH="$(sha "$DMG")" || exit $?; [[ "$LOCAL_HASH" == "$recorded" ]] || fail "Local DMG checksum mismatch"

public_get() {
  local url="$1" out="$2" headers="${3:-}" status args
  args=(--silent --show-error --output "$out" --write-out '%{http_code}')
  [[ -z "$headers" ]] || args+=(--dump-header "$headers")
  if status="$("$CURL_BIN" "${args[@]}" "$url")"; then printf '%s' "$status"; else code=$?; echo "Public GET failed" >&2; return "$code"; fi
}
authenticated_curl() { printf '%s\n' "$AUTH" | "$CURL_BIN" "$@"; }
signed_get() {
  local key="$1" out="$2" headers="${3:-}" args status
  args=(--config - --silent --show-error --aws-sigv4 aws:amz:auto:s3 --request GET --output "$out" --write-out '%{http_code}')
  [[ -z "$headers" ]] || args+=(--dump-header "$headers")
  if status="$(authenticated_curl "${args[@]}" "$ORIGIN$key")"; then printf '%s' "$status"; else code=$?; echo "Authenticated R2 GET failed" >&2; return "$code"; fi
}
signed_put() {
  local key="$1" file="$2" type="$3" cache="$4" condition="$5" status
  local out="$TMP/put-${key//\//-}"
  [[ "$condition" == 'If-None-Match: *' || "$condition" =~ ^If-Match:[[:space:]]\"[A-Za-z0-9._:-]+\"$ ]] || return 64
  if status="$(authenticated_curl --config - --silent --show-error --aws-sigv4 aws:amz:auto:s3 --request PUT --header "$condition" --header "Content-Type: $type" --header "Cache-Control: $cache" --upload-file "$file" --output "$out" --write-out '%{http_code}' "$ORIGIN$key")"; then printf '%s' "$status"; else code=$?; echo "Authenticated R2 PUT failed" >&2; return "$code"; fi
}
etag() {
  ruby -e '
    values=File.readlines(ARGV[0]).map{|l| m=l.match(/\AETag:\s*(.+?)\r?\n?\z/i);m&&m[1]}.compact
    exit 1 unless values.length==1 && values[0].match?(/\A"[A-Za-z0-9._:-]+"\z/); print values[0]
  ' "$1"
}
compare_versions() {
  ruby -e 'a,b=ARGV.map{|v|v.split(".").map(&:to_i)}; n=[a.length,b.length].max; a+=Array.new(n-a.length,0); b+=Array.new(n-b.length,0); print(a<=>b)' "$1" "$2"
}
validate_remote_metadata() {
  local remote_url="$1" remote_length="$2" remote_build="$3" remote_version="$4"
  [[ "$remote_version" =~ ^[0-9]+([.][0-9]+){1,2}$ && "$remote_build" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || return 1
  [[ "$remote_length" =~ ^[1-9][0-9]*$ && "$remote_url" == "${PUBLIC}UpdateBar-${remote_version}-macos-arm64.dmg" ]]
}

# Read public and authoritative mutable state before any upload so rollback/conflict cannot create orphan artifacts.
PUBLIC_PRE="$TMP/public-pre.xml"; PUBLIC_PRE_HEADERS="$TMP/public-pre.headers"
PUBLIC_PRE_STATUS="$(public_get "${PUBLIC}appcast.xml" "$PUBLIC_PRE" "$PUBLIC_PRE_HEADERS")" || exit $?
PRE="$TMP/pre.xml"; PRE_HEADERS="$TMP/pre.headers"; PRE_STATUS="$(signed_get appcast.xml "$PRE" "$PRE_HEADERS")" || exit $?
[[ "$PUBLIC_PRE_STATUS" == "$PRE_STATUS" ]] || fail "Public and authoritative appcast state disagree"
case "$PRE_STATUS" in
  404) PRE_ETAG='';;
  200)
    appcast_metadata "$PUBLIC_PRE" >/dev/null || fail "Public appcast is malformed"
    "$CMP_BIN" -s "$PUBLIC_PRE" "$PRE" || fail "Public and authoritative appcast bytes disagree"
    etag "$PUBLIC_PRE_HEADERS" >/dev/null || fail "Public appcast ETag is missing, weak, duplicated, or unsafe"
    PRE_META="$(appcast_metadata "$PRE")" || fail "Remote appcast is malformed"
    IFS=$'\t' read -r REMOTE_URL REMOTE_LENGTH REMOTE_BUILD REMOTE_VERSION REMOTE_SIGNATURE <<<"$PRE_META"
    validate_remote_metadata "$REMOTE_URL" "$REMOTE_LENGTH" "$REMOTE_BUILD" "$REMOTE_VERSION" || fail "Remote appcast metadata is unsafe"
    comparison="$(compare_versions "$REMOTE_VERSION" "$version")"
    [[ "$comparison" -le 0 ]] || fail "Refusing appcast rollback from $REMOTE_VERSION to $version"
    if [[ "$comparison" == 0 ]]; then "$CMP_BIN" -s "$APPCAST" "$PRE" && IDENTICAL=1 || fail "Same version has different appcast bytes or signature"; else IDENTICAL=0; fi
    PRE_ETAG="$(etag "$PRE_HEADERS")" || fail "Remote appcast ETag is missing, weak, duplicated, or unsafe"
    ;;
  *) fail "Authoritative appcast GET returned HTTP $PRE_STATUS";;
esac
IDENTICAL="${IDENTICAL:-0}"

verify_bytes() {
  local key="$1" local_file="$2" kind="$3" status
  local remote="$TMP/origin-$key"
  status="$(signed_get "$key" "$remote")" || return $?
  [[ "$status" == 200 ]] || fail "Authoritative immutable GET returned HTTP $status"
  if [[ "$kind" == dmg ]]; then [[ "$(sha "$remote")" == "$LOCAL_HASH" ]] || fail "Immutable DMG conflict"; else "$CMP_BIN" -s "$local_file" "$remote" || fail "Immutable checksum conflict"; fi
}
publish_immutable() {
  local key="$1" file="$2" type="$3" kind="$4" public_status origin_status put_status
  local probe="$TMP/public-$key" origin_probe="$TMP/origin-pre-$key"
  origin_status="$(signed_get "$key" "$origin_probe")" || return $?
  case "$origin_status" in
    200)
      if [[ "$kind" == dmg ]]; then [[ "$(sha "$origin_probe")" == "$LOCAL_HASH" ]] || fail "Immutable DMG conflict"; else "$CMP_BIN" -s "$file" "$origin_probe" || fail "Immutable checksum conflict"; fi
      public_status="$(public_get "$PUBLIC$key" "$probe")" || return $?
      [[ "$public_status" == 200 ]] || fail "Public immutable object is unavailable"
      if [[ "$kind" == dmg ]]; then [[ "$(sha "$probe")" == "$LOCAL_HASH" ]] || fail "Public immutable DMG conflict"; else "$CMP_BIN" -s "$file" "$probe" || fail "Public immutable checksum conflict"; fi
      return
      ;;
    404) ;;
    *) fail "Authoritative immutable GET returned HTTP $origin_status";;
  esac
  public_status="$(public_get "$PUBLIC$key" "$probe")" || return $?
  [[ "$public_status" == 404 ]] || fail "Public and authoritative immutable state disagree"
  put_status="$(signed_put "$key" "$file" "$type" 'public, max-age=31536000, immutable' 'If-None-Match: *')" || return $?
  [[ "$put_status" == 200 || "$put_status" == 201 || "$put_status" == 204 || "$put_status" == 412 ]] || fail "Immutable PUT returned HTTP $put_status"
  verify_bytes "$key" "$file" "$kind"
}

publish_immutable "$NAME" "$DMG" application/x-apple-diskimage dmg
publish_immutable "$NAME.sha256" "$CHECKSUM" text/plain checksum
for key in "$NAME" "$NAME.sha256"; do
  probe="$TMP/final-$key"; [[ "$(public_get "$PUBLIC$key" "$probe")" == 200 ]] || fail "Public immutable verification failed"
  if [[ "$key" == "$NAME" ]]; then [[ "$(sha "$probe")" == "$LOCAL_HASH" ]] || fail "Final public DMG bytes mismatch"; else "$CMP_BIN" -s "$CHECKSUM" "$probe" || fail "Final public checksum bytes mismatch"; fi
done

if [[ "$IDENTICAL" != 1 ]]; then
  CURRENT="$TMP/current.xml"; HEADERS="$TMP/current.headers"; CURRENT_STATUS="$(signed_get appcast.xml "$CURRENT" "$HEADERS")" || exit $?
  if [[ -z "$PRE_ETAG" ]]; then [[ "$CURRENT_STATUS" == 404 ]] || fail "Appcast changed concurrently"; condition='If-None-Match: *'
  else [[ "$CURRENT_STATUS" == 200 ]] || fail "Appcast changed concurrently"; current_etag="$(etag "$HEADERS")" || fail "Current appcast ETag is unsafe"; [[ "$current_etag" == "$PRE_ETAG" ]] || fail "Appcast changed concurrently"; "$CMP_BIN" -s "$CURRENT" "$PRE" || fail "Appcast bytes changed concurrently"; condition="If-Match: $PRE_ETAG"; fi
  PUT_STATUS="$(signed_put appcast.xml "$APPCAST" application/xml 'public, max-age=60' "$condition")" || exit $?
  [[ "$PUT_STATUS" == 200 || "$PUT_STATUS" == 201 || "$PUT_STATUS" == 204 ]] || fail "Conditional appcast publication failed with HTTP $PUT_STATUS"
fi

FINAL="$TMP/final-appcast.xml"; FINAL_HEADERS="$TMP/final-appcast.headers"; [[ "$(signed_get appcast.xml "$FINAL" "$FINAL_HEADERS")" == 200 ]] || fail "Final authoritative appcast is unavailable"
etag "$FINAL_HEADERS" >/dev/null || fail "Final authoritative appcast ETag is unsafe"; "$CMP_BIN" -s "$APPCAST" "$FINAL" || fail "Final authoritative appcast bytes mismatch"
PUBLIC_APPCAST="$TMP/public-appcast.xml"; PUBLIC_APPCAST_HEADERS="$TMP/public-appcast.headers"; [[ "$(public_get "${PUBLIC}appcast.xml" "$PUBLIC_APPCAST" "$PUBLIC_APPCAST_HEADERS")" == 200 ]] || fail "Public appcast is unavailable"
etag "$PUBLIC_APPCAST_HEADERS" >/dev/null || fail "Final public appcast ETag is unsafe"
"$CMP_BIN" -s "$APPCAST" "$PUBLIC_APPCAST" || fail "Public appcast bytes mismatch"
printf '%sappcast.xml\n' "$PUBLIC"
