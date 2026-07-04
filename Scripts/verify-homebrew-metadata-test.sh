#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

source version.env

formula_asset="updatebar-${UPDATEBAR_VERSION}-macos-arm64.tar.gz"
cask_asset="UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.app.tar.gz"

printf 'not a release archive\n' > "$TMP_DIR/$formula_asset"
printf 'not a cask archive\n' > "$TMP_DIR/$cask_asset"
printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "$formula_asset" > "$TMP_DIR/$formula_asset.sha256"
printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "$cask_asset" > "$TMP_DIR/$cask_asset.sha256"

OUTPUT="$TMP_DIR/static-only.out"
UPDATEBAR_VERIFY_STATIC_ONLY=1 bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$OUTPUT" 2>&1

if grep -Eq 'warning:|checksum mismatch|SHA mismatch' "$OUTPUT"; then
  echo "static-only metadata verification should not compare local dist checksums" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "release metadata verification passed for version $UPDATEBAR_VERSION" "$OUTPUT"; then
  echo "static-only metadata verification did not report success" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

echo "homebrew metadata behavior ok"
