#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/updatebar-publish-test.XXXXXX")" && pwd -P)"; trap 'rm -rf "$T"' EXIT
R="$T/root"; B="$T/bin"; REMOTE="$T/remote"; LOG="$T/calls"; mkdir -p "$R/Scripts" "$R/dist/updates" "$B" "$REMOTE"
cp "$ROOT/Scripts/publish-update.sh" "$R/Scripts/publish-update.sh" 2>/dev/null || true
name=UpdateBar-0.5.0-macos-arm64.dmg; printf 'local dmg\n' >"$R/dist/updates/$name"; hash="$(shasum -a 256 "$R/dist/updates/$name"|awk '{print $1}')"; printf '%s  %s\n' "$hash" "$name" >"$R/dist/updates/$name.sha256"
make_appcast() { local version="$1" sig="${2:-Q0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQw==}"; cat >"$3" <<XML
<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://updates.updatebar.sonim1.com/UpdateBar-${version}-macos-arm64.dmg" length="$(stat -f %z "$R/dist/updates/$name")" sparkle:version="$version" sparkle:shortVersionString="$version" sparkle:edSignature="$sig" /></item></channel></rss>
XML
}
make_appcast 0.5.0 '' "$R/dist/updates/appcast.xml"

cat >"$B/observe" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for value in "$@"; do
  case "$value" in *ACCESS123*|*TOPSECRET*|*'user = "'*) echo 'R2 auth leaked in child argv' >&2; exit 43;; esac
done
while IFS='=' read -r _ value; do
  case "$value" in *ACCESS123*|*TOPSECRET*|*'user = "'*) echo 'R2 auth leaked in child environment' >&2; exit 43;; esac
done < <(/usr/bin/env)
printf 'child:%s\n' "$1" >>"$CHILD_LOG"
SH
cat >"$B/child" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
name="$(basename "$0")"
"$OBSERVER" "$name" "$@"
exec "/usr/bin/$name" "$@"
SH
chmod +x "$B/observe" "$B/child"
for child in ruby find stat wc tr shasum cmp mktemp; do cp "$B/child" "$B/$child"; done

cat >"$B/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
"$OBSERVER" curl "$@"
args=("$@"); printf 'curl:' >>"$CALL_LOG"; printf '%q ' "$@" >>"$CALL_LOG"; printf '\n' >>"$CALL_LOG"
[[ "${SCENARIO:-}" != network ]] || exit 42
method=GET; out=''; upload=''; headers=''; condition=''; url=''; prev=''
for a in "$@"; do
  [[ "$prev" == --request ]] && method="$a"; [[ "$prev" == --output ]] && out="$a"; [[ "$prev" == --upload-file ]] && upload="$a"; [[ "$prev" == --dump-header ]] && headers="$a"; [[ "$prev" == --header && "$a" == If-* ]] && condition="$a"; prev="$a"; url="$a"
done
if [[ " ${args[*]} " == *' --config - '* ]]; then IFS= read -r config || :; [[ "$config" == *'ACCESS123:TOPSECRET'* ]] || exit 40; [[ "${SCENARIO:-}" != auth ]] || exit 41; fi
key="${url##*/}"; path="$REMOTE_DIR/$key"
if [[ "$method" == GET ]]; then
  if [[ -f "$path" ]]; then
    if [[ "${SCENARIO:-}" == public-mismatch && "$url" == https://updates.* && "$key" == appcast.xml ]]; then printf '<bad' >"$out"; else cp "$path" "$out"; fi
    if [[ -n "$headers" ]]; then
      if [[ "${SCENARIO:-}" == unsafe-etag && "$key" == appcast.xml ]]; then printf 'ETag: W/"weak"\r\n' >"$headers"; else printf 'ETag: "%s"\r\n' "$(shasum -a 256 "$path"|awk '{print substr($1,1,16)}')" >"$headers"; fi
    fi
    printf 200
  else : >"$out"; [[ -z "$headers" ]] || : >"$headers"; printf 404; fi
  exit 0
fi
[[ "$method" == PUT ]] || exit 90
if [[ "$condition" == 'If-None-Match: *' && -f "$path" ]]; then printf 412; exit 0; fi
if [[ "$condition" == If-Match:* ]]; then
  [[ -f "$path" ]] || { printf 412; exit 0; }; current="\"$(shasum -a 256 "$path"|awk '{print substr($1,1,16)}')\""; [[ "$condition" == "If-Match: $current" ]] || { printf 412; exit 0; }
fi
[[ "${SCENARIO:-}" != concurrent || "$key" != appcast.xml ]] || { printf 412; exit 0; }
cp "$upload" "$path"; printf 200
SH
chmod +x "$B/curl" "$B"/ruby "$B"/find "$B"/stat "$B"/wc "$B"/tr "$B"/shasum "$B"/cmp "$B"/mktemp

run_case() {
  local scenario="$1" expected="$2"; : >"$LOG"; : >"$T/children"
  set +e
  env PATH="$B:$PATH" OBSERVER="$B/observe" CHILD_LOG="$T/children" AUTH=caller-exported-auth CALL_LOG="$LOG" REMOTE_DIR="$REMOTE" SCENARIO="$scenario" CURL_BIN="$B/curl" SHASUM_BIN="$B/shasum" CMP_BIN="$B/cmp" R2_ACCESS_KEY_ID=ACCESS123 R2_SECRET_ACCESS_KEY=TOPSECRET CLOUDFLARE_ACCOUNT_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$R/Scripts/publish-update.sh" >"$T/$scenario.out" 2>&1
  status=$?; set -e
  [[ "$status" == "$expected" ]] || { cat "$T/$scenario.out" >&2; echo "$scenario expected $expected got $status" >&2; exit 1; }
  ! grep -Eq 'ACCESS123|TOPSECRET|user = "' "$LOG" "$T/$scenario.out"
  grep -Fq 'child:' "$T/children"
  ! grep -Eq 'ACCESS123|TOPSECRET|user = "' "$T/children"
}

# RED: implementation is absent before production code.
run_case absent 0
[[ -f "$REMOTE/appcast.xml" ]] || { cat "$T/absent.out" >&2; cat "$LOG" >&2; exit 1; }
cmp "$R/dist/updates/appcast.xml" "$REMOTE/appcast.xml"
last_put="$(grep 'request PUT' "$LOG" | tail -1)"; [[ "$last_put" == *appcast.xml* ]]
run_case identical 0
! grep -Fq 'request PUT' "$LOG"

printf extra >"$R/dist/updates/extra"
run_case extra-artifact 1
rm "$R/dist/updates/extra"
cp "$R/dist/updates/appcast.xml" "$T/local-appcast"
printf '<bad' >"$R/dist/updates/appcast.xml"
run_case malformed-local 1
cp "$T/local-appcast" "$R/dist/updates/appcast.xml"

rm -rf "$REMOTE"; mkdir "$REMOTE"
sed 's/<rss /<feed /;s#</rss>#</feed>#' "$T/local-appcast" >"$R/dist/updates/appcast.xml"
run_case wrong-root-local 1
cp "$T/local-appcast" "$R/dist/updates/appcast.xml"
rm -rf "$REMOTE"; mkdir "$REMOTE"
make_appcast 0.4.0 '' "$T/wrong-root-remote.xml"
sed 's/<rss /<feed /;s#</rss>#</feed>#' "$T/wrong-root-remote.xml" >"$REMOTE/appcast.xml"
run_case wrong-root-public-origin 1

make_appcast 0.6.0 '' "$REMOTE/appcast.xml"; rm -f "$REMOTE/$name" "$REMOTE/$name.sha256"
run_case rollback 1
! grep -Fq 'request PUT' "$LOG"
make_appcast 0.5.0 'RERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERERA==' "$REMOTE/appcast.xml"
run_case same-conflict 1
make_appcast 0.4.0 '' "$REMOTE/appcast.xml"
run_case upgrade 0

run_case unsafe-etag 1
run_case public-mismatch 1
printf '<bad' >"$REMOTE/appcast.xml"
run_case malformed-remote 1

printf 'other\n' >"$REMOTE/$name"; rm -f "$REMOTE/appcast.xml"
run_case immutable-conflict 1
rm -rf "$REMOTE"; mkdir "$REMOTE"
run_case concurrent 1
run_case auth 41
run_case network 42
set +e
: >"$LOG"
CALL_LOG="$LOG" REMOTE_DIR="$REMOTE" CURL_BIN="$B/curl" R2_ACCESS_KEY_ID=ACCESS123 R2_SECRET_ACCESS_KEY=TOPSECRET CLOUDFLARE_ACCOUNT_ID=acct123 "$R/Scripts/publish-update.sh" >"$T/invalid-account.out" 2>&1
status=$?
set -e
[[ "$status" == 64 ]]
grep -Fq 'CLOUDFLARE_ACCOUNT_ID' "$T/invalid-account.out"
test ! -s "$LOG"
echo "publish update tests passed"
