#!/usr/bin/env bash
set -euo pipefail

[[ "$#" -eq 2 ]] || { echo 'usage: site-postdeploy-check.sh ORIGIN SOURCE_SHA' >&2; exit 64; }

origin="${1%/}"
source_sha="$2"
[[ "$origin" == 'https://updatebar.royjen.com' ]] || { echo "unexpected production origin: $origin" >&2; exit 64; }
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'source SHA must be 40 lowercase hexadecimal characters' >&2; exit 64; }

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

fetch() {
  curl --silent --show-error --location --max-time 30 \
    --header 'Cache-Control: no-cache' \
    --output "$body" --write-out '%{http_code}' "$1"
}

status="$(fetch "$origin/")"
[[ "$status" == 200 ]] || { echo "landing root returned HTTP $status" >&2; exit 1; }
grep -Fq '<title>UpdateBar | macOS App and CLI for Updating Developer Tools</title>' "$body" || {
  echo 'landing root is missing the expected title' >&2
  exit 1
}
grep -Fq '<link rel="canonical" href="https://updatebar.royjen.com/">' "$body" || {
  echo 'landing root is missing the production canonical URL' >&2
  exit 1
}

status="$(fetch "$origin/deployment-source.txt?source=$source_sha")"
[[ "$status" == 200 ]] || { echo "deployment source marker returned HTTP $status" >&2; exit 1; }
[[ "$(tr -d '\r\n' < "$body")" == "$source_sha" ]] || {
  echo 'production does not report the deployed source SHA' >&2
  exit 1
}

status="$(fetch "$origin/_deployment-check/$source_sha")"
[[ "$status" == 404 ]] || { echo "missing route returned HTTP $status instead of 404" >&2; exit 1; }
grep -Fq '<title>Page not found | UpdateBar</title>' "$body" || {
  echo 'missing route did not serve the UpdateBar 404 page' >&2
  exit 1
}

echo "production landing verified at source $source_sha"
