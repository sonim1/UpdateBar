#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:-}"
SHA_FILE="${2:-${ARCHIVE}.sha256}"

if [[ -z "$ARCHIVE" ]]; then
  echo "usage: Scripts/verify-archive-checksum.sh <archive> [sha_file]" >&2
  exit 1
fi
if [[ ! -f "$SHA_FILE" ]]; then
  echo "missing checksum file: $SHA_FILE" >&2
  exit 1
fi

EXPECTED="$(awk 'NF { print $1; exit }' "$SHA_FILE")"
if [[ -z "$EXPECTED" ]]; then
  echo "empty checksum file: $SHA_FILE" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
else
  echo "shasum or sha256sum is required" >&2
  exit 1
fi

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "archive checksum mismatch: $ARCHIVE" >&2
  echo "  expected: $EXPECTED" >&2
  echo "  actual:   $ACTUAL" >&2
  exit 1
fi
