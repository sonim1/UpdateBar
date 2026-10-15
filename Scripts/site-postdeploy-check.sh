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
  curl --silent --show-error --location --max-time "${2:-30}" \
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

marker_ready=0
for attempt in {1..24}; do
  if status="$(fetch "$origin/deployment-source.txt?source=$source_sha" 5)" &&
    [[ "$status" == 200 ]] && [[ "$(tr -d '\r\n' < "$body")" == "$source_sha" ]]; then
    marker_ready=1
    break
  fi
  if [[ "$attempt" -lt 24 ]]; then
    echo "waiting for production source marker ($attempt/24, HTTP $status)" >&2
    sleep 5
  fi
done
[[ "$marker_ready" == 1 ]] || {
  echo "production source marker did not become ready (last HTTP $status)" >&2
  exit 1
}

status="$(fetch "$origin/_deployment-check/$source_sha")"
[[ "$status" == 404 ]] || { echo "missing route returned HTTP $status instead of 404" >&2; exit 1; }
grep -Fq '<title>Page not found | UpdateBar</title>' "$body" || {
  echo 'missing route did not serve the UpdateBar 404 page' >&2
  exit 1
}

echo "production landing verified at source $source_sha"
