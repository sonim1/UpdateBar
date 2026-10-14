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
    printf '%s\n' "$EXPECTED_SOURCE_SHA" > "$output"
    printf '200'
    ;;
  */_deployment-check/*)
    printf '%s\n' '<title>Page not found | UpdateBar</title>' > "$output"
    printf '404'
    ;;
  *) exit 22 ;;
esac
SH
chmod +x "$TMP/bin/curl"

source_sha='0123456789abcdef0123456789abcdef01234567'
PATH="$TMP/bin:$PATH" EXPECTED_SOURCE_SHA="$source_sha" bash "$CHECK" https://updatebar.royjen.com "$source_sha"

if PATH="$TMP/bin:$PATH" EXPECTED_SOURCE_SHA="$source_sha" bash "$CHECK" https://example.com "$source_sha" >/dev/null 2>&1; then
  echo 'post-deploy check accepted the wrong production origin' >&2
  exit 1
fi
if PATH="$TMP/bin:$PATH" EXPECTED_SOURCE_SHA="$source_sha" bash "$CHECK" https://updatebar.royjen.com invalid >/dev/null 2>&1; then
  echo 'post-deploy check accepted a non-canonical source SHA' >&2
  exit 1
fi

echo 'site post-deploy check tests passed'
