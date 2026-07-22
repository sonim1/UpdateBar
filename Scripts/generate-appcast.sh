#!/usr/bin/env bash
set -euo pipefail
set +x
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 0 ]] || { echo "Usage: Scripts/generate-appcast.sh" >&2; exit 64; }
VERSION_FILE="$ROOT/version.env"
[[ -f "$VERSION_FILE" && ! -L "$VERSION_FILE" ]] || { echo "version.env is missing or unsafe" >&2; exit 66; }
version_line=''; version_lines=0
while IFS= read -r line || [[ -n "$line" ]]; do version_lines=$((version_lines+1)); version_line="$line"; done <"$VERSION_FILE"
[[ "$version_lines" == 1 && "$version_line" =~ ^UPDATEBAR_VERSION=([0-9]+([.][0-9]+){1,2})$ ]] || { echo "version.env must contain exactly one canonical UPDATEBAR_VERSION assignment" >&2; exit 64; }
VERSION="${BASH_REMATCH[1]}"
DOMAIN="${UPDATE_DOMAIN:-updates.updatebar.sonim1.com}"
PUBLIC_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
PRIVATE_KEY="${SPARKLE_PRIVATE_ED_KEY:-}"
unset SPARKLE_PRIVATE_ED_KEY
export -n PRIVATE_KEY 2>/dev/null || :
ACCOUNT="${SPARKLE_KEY_ACCOUNT:-updatebar}"
DMG="$ROOT/dist/UpdateBar-${VERSION}-macos-arm64.dmg"
CHECKSUM="$DMG.sha256"
OUTPUT="$ROOT/dist/updates"
ARTIFACT_ROOT="$ROOT/.build/artifacts/sparkle/Sparkle"
SMOKE="${APP_DMG_SMOKE_BIN:-$ROOT/Scripts/app-dmg-smoke-test.sh}"
CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"
XCRUN_BIN="${XCRUN_BIN:-/usr/bin/xcrun}"
SPCTL_BIN="${SPCTL_BIN:-/usr/sbin/spctl}"
FILE_BIN="${FILE_BIN:-/usr/bin/file}"
HDIUTIL_BIN="${HDIUTIL_BIN:-/usr/bin/hdiutil}"
PLUTIL_BIN="${PLUTIL_BIN:-/usr/bin/plutil}"
REALPATH_BIN="${REALPATH_BIN:-realpath}"
RENAME_BIN="${RENAME_BIN:-/usr/bin/ruby}"
REMOVE_BIN="${REMOVE_BIN:-/usr/bin/ruby}"

fail() { echo "$1" >&2; exit "${2:-1}"; }
run() { local label="$1" status; shift; if "$@"; then return 0; else status=$?; echo "$label failed" >&2; return "$status"; fi; }
regular() { [[ -f "$1" && ! -L "$1" ]] || fail "Missing or unsafe $2: $1" 66; }

[[ "$VERSION" =~ ^[0-9]+([.][0-9]+){1,2}$ ]] || fail "Invalid UpdateBar version" 64
[[ "$DOMAIN" == updates.updatebar.sonim1.com ]] || fail "Update domain is fixed to updates.updatebar.sonim1.com" 64
ruby -rbase64 -e 'v=ARGV[0]; begin; b=Base64.strict_decode64(v); exit(b.bytesize==32 && Base64.strict_encode64(b)==v ? 0 : 1); rescue ArgumentError; exit 1; end' "$PUBLIC_KEY" || fail "SPARKLE_PUBLIC_ED_KEY must be canonical Base64 for 32 bytes" 64
regular "$DMG" DMG; regular "$CHECKSUM" checksum
[[ "$(cd "$(dirname "$DMG")" && pwd -P)/$(basename "$DMG")" == "$DMG" ]] || fail "DMG path is not canonical" 64
[[ "$(cd "$(dirname "$CHECKSUM")" && pwd -P)/$(basename "$CHECKSUM")" == "$CHECKSUM" ]] || fail "Checksum path is not canonical" 64

read -r recorded recorded_name extra <"$CHECKSUM" || fail "Unable to read checksum"
[[ -z "${extra:-}" && "$recorded" =~ ^[0-9a-f]{64}$ && "$recorded_name" == "$(basename "$DMG")" ]] || fail "Checksum must contain exactly one canonical record"
[[ "$(wc -l <"$CHECKSUM" | tr -d ' ')" == 1 ]] || fail "Checksum must contain exactly one record"
actual="$(shasum -a 256 "$DMG" | awk '{print $1}')" || exit $?
[[ "$actual" == "$recorded" ]] || fail "DMG checksum mismatch"

run "DMG smoke validation" env SPARKLE_PUBLIC_ED_KEY="$PUBLIC_KEY" UPDATEBAR_UPDATE_FEED_URL="https://$DOMAIN/appcast.xml" "$SMOKE" "$DMG" >/dev/null
run "DMG codesign verification" "$CODESIGN_BIN" --verify --deep --strict "$DMG"
run "DMG stapler validation" "$XCRUN_BIN" stapler validate "$DMG"
run "DMG Gatekeeper validation" "$SPCTL_BIN" -a -vv -t open --context context:primary-signature "$DMG"

ruby -rjson -e '
  p=JSON.parse(File.binread(ARGV[0])); pin=p.fetch("pins").find{|x| x["identity"]=="sparkle"};
  exit(pin && pin.dig("state","revision")=="b6496a74a087257ef5e6da1c5b29a447a60f5bd7" ? 0 : 1)
' "$ROOT/Package.resolved" || fail "Sparkle dependency is not pinned to the reviewed 2.9.4 commit"

tool_list="$(mktemp "${TMPDIR:-/tmp}/updatebar-appcast-tools.XXXXXX")"; work=''; key_file=''; final=''; final_identity=''; final_owned=0; lock=''; lock_owned=0
metadata_dir=''; metadata_mount=''; metadata_attached=0
remove_exact_directory() {
  local path="$1" expected_identity="$2"
  "$REMOVE_BIN" -rfileutils -e '
    path, expected_identity = ARGV
    begin
      stat = File.lstat(path)
    rescue Errno::ENOENT
      exit 0
    end
    actual_identity = "#{stat.dev}:#{stat.ino}"
    abort "Refusing to remove a replaced directory" unless actual_identity == expected_identity && stat.directory? && !stat.symlink?
    FileUtils.remove_entry_secure(path, true)
  ' "$path" "$expected_identity"
}
cleanup() {
  status=$?; trap - EXIT HUP INT TERM
  if [[ "$metadata_attached" == 1 ]]; then "$HDIUTIL_BIN" detach "$metadata_mount" >/dev/null 2>&1 || :; fi
  [[ -z "$metadata_dir" || ! -d "$metadata_dir" ]] || rm -rf "$metadata_dir"
  [[ -z "$key_file" ]] || rm -f "$key_file"
  [[ -z "$work" || ! -d "$work" ]] || rm -rf "$work"
  if [[ "$final_owned" == 1 && -n "$final" ]]; then
    remove_exact_directory "$final" "$final_identity" || echo "Preserving replaced appcast finalization path: $final" >&2
  fi
  if [[ "$lock_owned" == 1 && -d "$lock" && ! -L "$lock" ]]; then rmdir "$lock" || :; fi
  rm -f "$tool_list"
  exit "$status"
}
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM

# Bind the appcast version/build to the actual app inside the validated DMG.
metadata_dir="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-dmg-metadata.XXXXXX")"
metadata_mount="$metadata_dir/mount"; mkdir "$metadata_mount"; metadata_mount="$($REALPATH_BIN "$metadata_mount")"
if "$HDIUTIL_BIN" attach -mountpoint "$metadata_mount" -plist -nobrowse -readonly "$DMG" >"$metadata_dir/attach.plist"; then metadata_attached=1; else status=$?; echo "DMG metadata mount failed" >&2; exit "$status"; fi
reported_mount="$(ruby -e '
  raw=File.binread(ARGV[0]); values=raw.scan(/<key>\s*mount-point\s*<\/key>\s*<string>([^<]+)<\/string>/m).flatten
  exit 1 unless values.length==1 && values[0].start_with?("/") && !values[0].match?(/[\0\r\n]/); print values[0]
' "$metadata_dir/attach.plist")" || fail "DMG metadata mount response is malformed"
[[ "$reported_mount" == "$metadata_mount" && "$($REALPATH_BIN "$reported_mount")" == "$metadata_mount" ]] || fail "DMG metadata mounted outside the private mount point"
mounted_plist="$metadata_mount/UpdateBar.app/Contents/Info.plist"; regular "$mounted_plist" "mounted app Info.plist"
case "$($REALPATH_BIN "$mounted_plist")" in "$metadata_mount"/*) ;; *) fail "Mounted Info.plist escapes the DMG";; esac
plist_value() { "$PLUTIL_BIN" -extract "$1" raw -o - "$mounted_plist"; }
DMG_VERSION="$(plist_value CFBundleShortVersionString)" || exit $?
DMG_BUILD="$(plist_value CFBundleVersion)" || exit $?
DMG_FEED="$(plist_value SUFeedURL)" || exit $?
DMG_KEY="$(plist_value SUPublicEDKey)" || exit $?
[[ "$DMG_VERSION" == "$VERSION" && "$DMG_BUILD" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || fail "Mounted app version/build is invalid"
[[ "$DMG_FEED" == "https://$DOMAIN/appcast.xml" && "$DMG_KEY" == "$PUBLIC_KEY" ]] || fail "Mounted app Sparkle feed/key mismatch"
run "DMG metadata detach" "$HDIUTIL_BIN" detach "$metadata_mount" >/dev/null; metadata_attached=0
rm -rf "$metadata_dir"; metadata_dir=''; metadata_mount=''

[[ -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || fail "Sparkle artifact root is missing or unsafe" 66
find "$ARTIFACT_ROOT" -type f -name generate_appcast -perm -111 -print0 >"$tool_list"
count=0; tool=''
while IFS= read -r -d '' candidate; do tool="$candidate"; count=$((count+1)); done <"$tool_list"
[[ "$count" == 1 ]] || fail "Expected exactly one Sparkle generate_appcast tool; found $count" 66
root_real="$(cd "$ARTIFACT_ROOT" && pwd -P)"; tool_real="$(cd "$(dirname "$tool")" && pwd -P)/$(basename "$tool")"
case "$tool_real" in "$root_real"/*) ;; *) fail "Sparkle tool escapes the artifact root" 66;; esac
"$FILE_BIN" "$tool" | grep -q 'Mach-O' || fail "Sparkle generate_appcast is not a macOS executable" 66

work="$(mktemp -d "$ROOT/dist/.generate-appcast-work.XXXXXX")"
name="$(basename "$DMG")"; staged="$work/$name"; staged_checksum="$work/$name.sha256"; cp "$DMG" "$staged"
staged_hash="$(shasum -a 256 "$staged" | awk '{print $1}')" || exit $?
[[ "$staged_hash" == "$recorded" ]] || fail "DMG changed while creating the signed staging snapshot"
printf '%s  %s\n' "$staged_hash" "$name" >"$staged_checksum"
appcast="$work/appcast.xml"
if [[ -n "$PRIVATE_KEY" ]]; then
  old_umask="$(umask)"; umask 077; key_file="$(mktemp "${TMPDIR:-/tmp}/updatebar-sparkle-key.XXXXXX")"; printf '%s\n' "$PRIVATE_KEY" >"$key_file"; chmod 600 "$key_file"; umask "$old_umask"
  ruby -rbase64 -e 'v=File.binread(ARGV[0]).chomp; begin; b=Base64.strict_decode64(v); exit(b.bytesize==32 && Base64.strict_encode64(b)==v ? 0 : 1); rescue ArgumentError; exit 1; end' "$key_file" || fail "SPARKLE_PRIVATE_ED_KEY is not a canonical 32-byte seed" 64
  if env -u SPARKLE_PRIVATE_ED_KEY -u PRIVATE_KEY "$tool" --ed-key-file "$key_file" --download-url-prefix "https://$DOMAIN/" -o "$appcast" "$work"; then :; else status=$?; echo "Sparkle generate_appcast failed" >&2; exit "$status"; fi
else
  run "Sparkle generate_appcast" "$tool" --account "$ACCOUNT" --download-url-prefix "https://$DOMAIN/" -o "$appcast" "$work"
fi
regular "$appcast" appcast

metadata="$(ruby -rrexml/document -rbase64 -e '
  begin
    raw=File.binread(ARGV[0]); abort if raw.include?("<!DOCTYPE"); d=REXML::Document.new(raw); ns="http://www.andymatuschak.org/xml-namespaces/sparkle"
    abort unless d.root && d.root.name=="rss" && d.root.namespaces["sparkle"]==ns
    items=[]; REXML::XPath.each(d,"//*[local-name()=\"item\"]"){|e| items<<e}; abort unless items.length==1
    es=[]; REXML::XPath.each(d,"//*[local-name()=\"enclosure\"]"){|e| es<<e}; abort unless es.length==1 && es[0].parent==items[0]
    e=es[0]; a=->(n){x=e.attributes.get_attribute_ns(ns,n); x && x.value}
    vals=[e.attributes["url"],e.attributes["length"],a.call("version"),a.call("shortVersionString"),a.call("edSignature")]
    abort if vals.any?{|v| v.nil? || v.include?("\t") || v.include?("\n")}; Base64.strict_decode64(vals[4]); puts vals.join("\t")
  rescue; exit 1; end
' "$appcast")" || fail "Generated appcast XML is malformed"
IFS=$'\t' read -r url length build short signature <<<"$metadata"
expected_url="https://$DOMAIN/$name"; bytes="$(stat -f '%z' "$staged")"
[[ "$url" == "$expected_url" && "$length" == "$bytes" ]] || fail "Appcast enclosure URL or length mismatch"
[[ "$short" == "$DMG_VERSION" && "$build" == "$DMG_BUILD" ]] || fail "Appcast version metadata mismatch"
ruby -rbase64 -e 'exit(Base64.strict_decode64(ARGV[0]).bytesize==64 ? 0 : 1)' "$signature" || fail "Appcast EdDSA signature is malformed"
swift='import Foundation; import CryptoKit; let a=CommandLine.arguments; guard let p=Data(base64Encoded:a[1]), let s=Data(base64Encoded:a[2]) else { exit(2) }; let k=try Curve25519.Signing.PublicKey(rawRepresentation:p); let d=try Data(contentsOf:URL(fileURLWithPath:a[3])); exit(k.isValidSignature(s, for:d) ? 0:1)'
run "EdDSA public-key verification" "$XCRUN_BIN" swift -e "$swift" "$PUBLIC_KEY" "$signature" "$staged"

final="$(mktemp -d "$ROOT/dist/.generate-appcast-final.XXXXXX")"
cp "$staged" "$final/$name"; cp "$staged_checksum" "$final/$name.sha256"; cp "$appcast" "$final/appcast.xml"
final_identity="$(/usr/bin/stat -f '%d:%i' "$final")"; final_owned=1
lock="$ROOT/dist/.generate-appcast.lock"; mkdir "$lock" || fail "Another appcast publication transaction is active"
lock_owned=1
if [[ -L "$OUTPUT" || ( -e "$OUTPUT" && ! -d "$OUTPUT" ) ]]; then fail "Unsafe update output destination"; fi
if [[ -d "$OUTPUT" ]]; then rename_mode=swap; else rename_mode=exclusive; fi
if rename_result="$("$RENAME_BIN" -rfiddle/import -e '
  source, destination, mode = ARGV
  source_stat = File.lstat(source)
  abort "Appcast source is not a real directory" unless source_stat.directory? && !source_stat.symlink?
  source_identity = "#{source_stat.dev}:#{source_stat.ino}"
  destination_identity = nil
  if mode == "exclusive"
    begin
      File.lstat(destination)
      abort "Appcast destination appeared during finalization"
    rescue Errno::ENOENT
    end
    flags = 0x00000004 # RENAME_EXCL
  elsif mode == "swap"
    destination_stat = File.lstat(destination)
    abort "Appcast destination changed during finalization" unless destination_stat.directory? && !destination_stat.symlink?
    destination_identity = "#{destination_stat.dev}:#{destination_stat.ino}"
    flags = 0x00000002 # RENAME_SWAP
  else
    abort "Unknown appcast rename mode"
  end
  module DarwinRename
    extend Fiddle::Importer
    dlload Fiddle.dlopen(nil)
    extern "int renameatx_np(int, const char *, int, const char *, unsigned int)"
  end
  result = DarwinRename.renameatx_np(-2, source, -2, destination, flags)
  if result != 0
    warn "renameatx_np failed with errno #{Fiddle.last_error}"
    exit 73
  end
  begin
    published_stat = File.lstat(destination)
    published_identity = "#{published_stat.dev}:#{published_stat.ino}"
  rescue Errno::ENOENT
    warn "Appcast destination disappeared after rename"
    exit 74
  end
  unless published_stat.directory? && !published_stat.symlink? && published_identity == source_identity
    warn "Appcast destination identity changed during rename"
    exit 74
  end
  if mode == "exclusive"
    begin
      File.lstat(source)
      warn "Appcast source still exists after exclusive rename"
      exit 74
    rescue Errno::ENOENT
    end
  else
    begin
      displaced_stat = File.lstat(source)
      displaced_identity = "#{displaced_stat.dev}:#{displaced_stat.ino}"
    rescue Errno::ENOENT
      warn "Displaced appcast directory disappeared after swap"
      exit 74
    end
    unless displaced_stat.directory? && !displaced_stat.symlink? && displaced_identity == destination_identity
      warn "Displaced appcast directory identity changed during swap"
      exit 74
    end
  end
  puts [source_identity, destination_identity || "-"].join("\t")
' "$final" "$OUTPUT" "$rename_mode")"; then :; else rename_status=$?; echo "Unable to finalize appcast output" >&2; exit "$rename_status"; fi
IFS=$'\t' read -r reported_final_identity reported_displaced_identity <<<"$rename_result"
[[ "$reported_final_identity" == "$final_identity" ]] || fail "Rename helper reported an unexpected source identity"
if [[ "$rename_mode" == swap ]]; then
  if remove_exact_directory "$final" "$reported_displaced_identity"; then :; else echo "Preserving replaced displaced appcast directory: $final" >&2; exit 74; fi
fi
final_owned=0; final=''; final_identity=''
rmdir "$lock"; lock_owned=0
printf '%s\n' "$OUTPUT/appcast.xml"
