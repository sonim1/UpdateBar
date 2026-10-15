#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/Scripts/site-postdeploy-check.sh"
[[ -x "$CHECK" ]] || { echo "site post-deploy check is missing or not executable" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=''
url="${!#}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "$url" in
  https://updatebar.royjen.com/)
    printf '%s\n' '<title>UpdateBar | macOS App and CLI for Updating Developer Tools</title>' '<link rel="canonical" href="https://updatebar.royjen.com/">' > "$output"
    printf '200'
    ;;
  *deployment-source.txt*)
    count=0
    [[ ! -f "$MARKER_STATE" ]] || count="$(cat "$MARKER_STATE")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$MARKER_STATE"
    case "$MARKER_MODE:$count" in
      delayed:1 | unavailable:*)
        : > "$output"
        printf '404'
        ;;
      delayed:2 | stale:*)
        printf '%040d\n' 0 > "$output"
        printf '200'
        ;;
      transport:1 | unreachable:*) exit 7 ;;
      *)
        printf '%s\n' "$EXPECTED_SOURCE_SHA" > "$output"
        printf '200'
        ;;
    esac
    ;;
  */_deployment-check/*)
    printf '%s\n' '<title>Page not found | UpdateBar</title>' > "$output"
    printf '%s' "${POSTDEPLOY_404_STATUS:-404}"
    ;;
  *) exit 22 ;;
esac
SH
chmod +x "$TMP/bin/curl"
cat > "$TMP/bin/sleep" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$RETRY_SLEEP_STATE"
SH
chmod +x "$TMP/bin/sleep"

source_sha='0123456789abcdef0123456789abcdef01234567'
run_check() {
  printf '0\n' > "$TMP/marker-state"
  : > "$TMP/sleep-state"
  PATH="$TMP/bin:$PATH" EXPECTED_SOURCE_SHA="$source_sha" \
    MARKER_MODE="$1" MARKER_STATE="$TMP/marker-state" RETRY_SLEEP_STATE="$TMP/sleep-state" \
    bash "$CHECK" https://updatebar.royjen.com "$source_sha" > "$TMP/check.log" 2>&1
}

run_check ready
[[ "$(cat "$TMP/marker-state")" == 1 && ! -s "$TMP/sleep-state" ]]

if ! run_check delayed; then
  cat "$TMP/check.log" >&2
  echo 'post-deploy check must wait through a missing and then stale source marker' >&2
  exit 1
fi
[[ "$(cat "$TMP/marker-state")" == 3 ]]
[[ "$(wc -l < "$TMP/sleep-state" | tr -d ' ')" == 2 ]]

if ! run_check transport; then
  cat "$TMP/check.log" >&2
  echo 'post-deploy check must retry a transient source fetch failure' >&2
  exit 1
fi
[[ "$(cat "$TMP/marker-state")" == 2 ]]

for mode in unavailable stale unreachable; do
  if run_check "$mode"; then
    echo "post-deploy check accepted a permanently $mode source marker" >&2
    exit 1
  fi
  [[ "$(cat "$TMP/marker-state")" == 24 ]]
  [[ "$(wc -l < "$TMP/sleep-state" | tr -d ' ')" == 23 ]]
  [[ "$(sort -u "$TMP/sleep-state")" == 5 ]]
done

if POSTDEPLOY_404_STATUS=200 run_check ready; then
  echo 'post-deploy check accepted a missing route with HTTP 200' >&2
  exit 1
fi

if PATH="$TMP/bin:$PATH" EXPECTED_SOURCE_SHA="$source_sha" bash "$CHECK" https://example.com "$source_sha" >/dev/null 2>&1; then
  echo 'post-deploy check accepted the wrong production origin' >&2
  exit 1
fi
if PATH="$TMP/bin:$PATH" EXPECTED_SOURCE_SHA="$source_sha" bash "$CHECK" https://updatebar.royjen.com invalid >/dev/null 2>&1; then
  echo 'post-deploy check accepted a non-canonical source SHA' >&2
  exit 1
fi

echo 'site post-deploy check tests passed'
