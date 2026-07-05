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

archive="$TMP_DIR/archive.tar.gz"
bad_sha_file="$TMP_DIR/archive.tar.gz.sha256"
bad_output="$TMP_DIR/bad-sha-output.txt"
printf 'not a real archive\n' > "$archive"
printf 'not-a-sha  archive.tar.gz\n' > "$bad_sha_file"

set +e
bash Scripts/verify-archive-checksum.sh "$archive" "$bad_sha_file" >"$bad_output" 2>&1
bad_rc=$?
set -e

if [[ "$bad_rc" -eq 0 ]]; then
  echo "verify-archive-checksum accepted an invalid checksum file" >&2
  cat "$bad_output" >&2
  exit 1
fi

if ! grep -Fq "checksum file did not contain a 64-character lowercase hex SHA" "$bad_output"; then
  echo "verify-archive-checksum invalid-checksum error was not clear" >&2
  cat "$bad_output" >&2
  exit 1
fi

echo "archive checksum verification behavior ok"
