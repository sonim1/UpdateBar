#!/usr/bin/env bash
set -euo pipefail

TAR_BIN="${1:-tar}"

if "$TAR_BIN" --version 2>/dev/null | grep -qi "gnu tar"; then
  printf '%s\n' \
    --format ustar \
    --owner=0 \
    --group=0 \
    --numeric-owner
else
  printf '%s\n' \
    --format ustar \
    --uid 0 \
    --gid 0 \
    --uname root \
    --gname wheel
fi
