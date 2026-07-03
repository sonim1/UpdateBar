#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

missing_archive="$TMP_DIR/missing.tar.gz"
sha_file="$missing_archive.sha256"
output="$TMP_DIR/output.txt"

printf '%064d  missing.tar.gz\n' 0 > "$sha_file"

set +e
bash Scripts/verify-archive-checksum.sh "$missing_archive" "$sha_file" >"$output" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "verify-archive-checksum accepted a missing archive" >&2
  cat "$output" >&2
  exit 1
fi

if ! grep -Fq "missing archive: $missing_archive" "$output"; then
  echo "verify-archive-checksum missing-archive error was not clear" >&2
  cat "$output" >&2
  exit 1
fi

echo "archive checksum verification behavior ok"
