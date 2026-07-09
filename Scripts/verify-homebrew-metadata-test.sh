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

cat > "$TMP_DIR/bad-formula.rb" <<EOF
class Updatebar < Formula
  version "$UPDATEBAR_VERSION"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$UPDATEBAR_VERSION/$formula_asset"
  sha256 "not-a-sha"
end
EOF

BAD_OUTPUT="$TMP_DIR/bad-sha.out"
set +e
UPDATEBAR_VERIFY_STATIC_ONLY=1 \
UPDATEBAR_HOMEBREW_FORMULA_PATH="$TMP_DIR/bad-formula.rb" \
bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$BAD_OUTPUT" 2>&1
bad_status=$?
set -e

if [[ "$bad_status" -eq 0 ]]; then
  echo "invalid Homebrew formula sha256 was accepted" >&2
  cat "$BAD_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "formula sha256 is not a 64-character lowercase hex value" "$BAD_OUTPUT"; then
  echo "invalid Homebrew formula sha256 did not report the expected error" >&2
  cat "$BAD_OUTPUT" >&2
  exit 1
fi

cat > "$TMP_DIR/bad-cask.rb" <<EOF
cask "updatebar-app" do
  version "$UPDATEBAR_VERSION"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$UPDATEBAR_VERSION/UpdateBar-#{version}-macos-arm64.app.tar.gz"
  sha256 "not-a-sha"
end
EOF

BAD_CASK_OUTPUT="$TMP_DIR/bad-cask-sha.out"
set +e
UPDATEBAR_VERIFY_STATIC_ONLY=1 \
UPDATEBAR_HOMEBREW_CASK_PATH="$TMP_DIR/bad-cask.rb" \
bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$BAD_CASK_OUTPUT" 2>&1
bad_cask_status=$?
set -e

if [[ "$bad_cask_status" -eq 0 ]]; then
  echo "invalid Homebrew cask sha256 was accepted" >&2
  cat "$BAD_CASK_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "cask sha256 is not a 64-character lowercase hex value" "$BAD_CASK_OUTPUT"; then
  echo "invalid Homebrew cask sha256 did not report the expected error" >&2
  cat "$BAD_CASK_OUTPUT" >&2
  exit 1
fi

cat > "$TMP_DIR/bad-formula-url.rb" <<EOF
class Updatebar < Formula
  version "$UPDATEBAR_VERSION"
  url "https://example.test/releases/v$UPDATEBAR_VERSION/$formula_asset"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF

BAD_URL_OUTPUT="$TMP_DIR/bad-formula-url.out"
set +e
UPDATEBAR_VERIFY_STATIC_ONLY=1 \
UPDATEBAR_HOMEBREW_FORMULA_PATH="$TMP_DIR/bad-formula-url.rb" \
bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$BAD_URL_OUTPUT" 2>&1
bad_url_status=$?
set -e

if [[ "$bad_url_status" -eq 0 ]]; then
  echo "invalid Homebrew formula release URL was accepted" >&2
  cat "$BAD_URL_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "formula URL must use https://github.com/sonim1/UpdateBar/releases/download/v$UPDATEBAR_VERSION/" "$BAD_URL_OUTPUT"; then
  echo "invalid Homebrew formula release URL did not report the expected error" >&2
  cat "$BAD_URL_OUTPUT" >&2
  exit 1
fi

cat > "$TMP_DIR/bad-cask-url.rb" <<EOF
cask "updatebar-app" do
  version "$UPDATEBAR_VERSION"
  url "https://example.test/releases/v#{version}/UpdateBar-#{version}-macos-arm64.app.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF

BAD_CASK_URL_OUTPUT="$TMP_DIR/bad-cask-url.out"
set +e
UPDATEBAR_VERIFY_STATIC_ONLY=1 \
UPDATEBAR_HOMEBREW_CASK_PATH="$TMP_DIR/bad-cask-url.rb" \
bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$BAD_CASK_URL_OUTPUT" 2>&1
bad_cask_url_status=$?
set -e

if [[ "$bad_cask_url_status" -eq 0 ]]; then
  echo "invalid Homebrew cask release URL was accepted" >&2
  cat "$BAD_CASK_URL_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "cask URL must use https://github.com/sonim1/UpdateBar/releases/download/v$UPDATEBAR_VERSION/" "$BAD_CASK_URL_OUTPUT"; then
  echo "invalid Homebrew cask release URL did not report the expected error" >&2
  cat "$BAD_CASK_URL_OUTPUT" >&2
  exit 1
fi

cat > "$TMP_DIR/bad-formula-asset.rb" <<EOF
class Updatebar < Formula
  version "$UPDATEBAR_VERSION"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$UPDATEBAR_VERSION/$cask_asset"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF

BAD_FORMULA_ASSET_OUTPUT="$TMP_DIR/bad-formula-asset.out"
set +e
UPDATEBAR_VERIFY_STATIC_ONLY=1 \
UPDATEBAR_HOMEBREW_FORMULA_PATH="$TMP_DIR/bad-formula-asset.rb" \
bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$BAD_FORMULA_ASSET_OUTPUT" 2>&1
bad_formula_asset_status=$?
set -e

if [[ "$bad_formula_asset_status" -eq 0 ]]; then
  echo "invalid Homebrew formula asset name was accepted" >&2
  cat "$BAD_FORMULA_ASSET_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "formula URL must end with $formula_asset" "$BAD_FORMULA_ASSET_OUTPUT"; then
  echo "invalid Homebrew formula asset name did not report the expected error" >&2
  cat "$BAD_FORMULA_ASSET_OUTPUT" >&2
  exit 1
fi

cat > "$TMP_DIR/bad-cask-asset.rb" <<EOF
cask "updatebar-app" do
  version "$UPDATEBAR_VERSION"
  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/$formula_asset"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF

BAD_CASK_ASSET_OUTPUT="$TMP_DIR/bad-cask-asset.out"
set +e
UPDATEBAR_VERIFY_STATIC_ONLY=1 \
UPDATEBAR_HOMEBREW_CASK_PATH="$TMP_DIR/bad-cask-asset.rb" \
bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$BAD_CASK_ASSET_OUTPUT" 2>&1
bad_cask_asset_status=$?
set -e

if [[ "$bad_cask_asset_status" -eq 0 ]]; then
  echo "invalid Homebrew cask asset name was accepted" >&2
  cat "$BAD_CASK_ASSET_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "cask URL must end with $cask_asset" "$BAD_CASK_ASSET_OUTPUT"; then
  echo "invalid Homebrew cask asset name did not report the expected error" >&2
  cat "$BAD_CASK_ASSET_OUTPUT" >&2
  exit 1
fi

# Strict mode with real (mismatching) archives must fail on SHA equality...
STRICT_OUTPUT="$TMP_DIR/strict.out"
set +e
UPDATEBAR_VERIFY_STRICT=1 \
bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$STRICT_OUTPUT" 2>&1
strict_status=$?
set -e

if [[ "$strict_status" -eq 0 ]]; then
  echo "strict verification accepted mismatching archive checksums" >&2
  cat "$STRICT_OUTPUT" >&2
  exit 1
fi

# ...but pass with UPDATEBAR_VERIFY_SKIP_SHA_EQUALITY=1 when only the
# committed formula/cask SHA equality differs (checksum files must still
# match the archives).
rehash() {
  local asset="$1"
  if command -v shasum >/dev/null 2>&1; then
    (cd "$TMP_DIR" && shasum -a 256 "$asset" > "$asset.sha256")
  else
    (cd "$TMP_DIR" && sha256sum "$asset" > "$asset.sha256")
  fi
}
rehash "$formula_asset"
rehash "$cask_asset"

SKIP_OUTPUT="$TMP_DIR/skip-sha-equality.out"
UPDATEBAR_VERIFY_STRICT=1 \
UPDATEBAR_VERIFY_SKIP_SHA_EQUALITY=1 \
bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$SKIP_OUTPUT" 2>&1

if ! grep -Fq "release metadata verification passed for version $UPDATEBAR_VERSION" "$SKIP_OUTPUT"; then
  echo "skip-sha-equality verification did not report success" >&2
  cat "$SKIP_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "formula SHA mismatch (skipped)" "$SKIP_OUTPUT"; then
  echo "skip-sha-equality verification did not warn about the formula SHA" >&2
  cat "$SKIP_OUTPUT" >&2
  exit 1
fi

# Corrupt checksum files must still fail even when SHA equality is skipped.
printf '1111111111111111111111111111111111111111111111111111111111111111  %s\n' "$formula_asset" > "$TMP_DIR/$formula_asset.sha256"
CORRUPT_OUTPUT="$TMP_DIR/corrupt-checksum.out"
set +e
UPDATEBAR_VERIFY_STRICT=1 \
UPDATEBAR_VERIFY_SKIP_SHA_EQUALITY=1 \
bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$CORRUPT_OUTPUT" 2>&1
corrupt_status=$?
set -e

if [[ "$corrupt_status" -eq 0 ]]; then
  echo "skip-sha-equality verification accepted a corrupt archive checksum" >&2
  cat "$CORRUPT_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "CLI archive checksum mismatch" "$CORRUPT_OUTPUT"; then
  echo "corrupt archive checksum did not report the expected error" >&2
  cat "$CORRUPT_OUTPUT" >&2
  exit 1
fi

echo "homebrew metadata behavior ok"
