#!/usr/bin/env bash
set -euo pipefail
set +x

[[ $# -eq 1 ]] || { echo 'Usage: Scripts/dispatch-homebrew-update.sh v<version>' >&2; exit 64; }
TAG="$1"
[[ "$TAG" =~ ^v[0-9]+([.][0-9]+){1,2}$ ]] || { echo 'Release tag must match v<version>' >&2; exit 64; }
[[ -n "${TAP_GH_TOKEN:-}" ]] || { echo 'TAP_GH_TOKEN is required' >&2; exit 64; }
GH_BIN="${GH_BIN:-gh}"

GH_TOKEN="$TAP_GH_TOKEN" \
TAP_GH_TOKEN='' \
GH_HOST='github.com' \
GH_REPO='sonim1/homebrew-tap' \
"$GH_BIN" api \
  --hostname github.com \
  --method POST \
  repos/sonim1/homebrew-tap/dispatches \
  -f event_type=homebrew_release \
  -f 'client_payload[repository]=sonim1/UpdateBar' \
  -f "client_payload[tag]=$TAG"
