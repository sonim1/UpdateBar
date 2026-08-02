#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# shellcheck source=/dev/null
source version.env

published_snapshot_version="$(awk '$1 == "version" { gsub(/"/, "", $2); print $2; exit }' Packaging/homebrew/updatebar.rb)"
formula_asset="updatebar-${UPDATEBAR_VERSION}-macos-arm64.tar.gz"
cask_asset="UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.app.tar.gz"
published_formula_asset="updatebar-${published_snapshot_version}-macos-arm64.tar.gz"
published_cask_asset="UpdateBar-${published_snapshot_version}-macos-arm64.app.tar.gz"

printf 'not a release archive\n' > "$TMP_DIR/$formula_asset"
printf 'not a cask DMG\n' > "$TMP_DIR/$cask_asset"
printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "$formula_asset" > "$TMP_DIR/$formula_asset.sha256"
printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "$cask_asset" > "$TMP_DIR/$cask_asset.sha256"

OUTPUT="$TMP_DIR/static-only.out"
UPDATEBAR_VERIFY_STATIC_ONLY=1 bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$OUTPUT" 2>&1

if grep -Eq 'warning:|checksum mismatch|SHA mismatch' "$OUTPUT"; then
  echo "static-only metadata verification should not compare local dist checksums" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "release metadata verification passed for version $published_snapshot_version" "$OUTPUT"; then
  echo "static-only metadata verification did not report success" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

snapshot_version="0.6.2"
if [[ "$snapshot_version" == "$UPDATEBAR_VERSION" ]]; then
  echo "snapshot regression must use a version older than version.env" >&2
  exit 1
fi
snapshot_formula_asset="updatebar-${snapshot_version}-macos-arm64.tar.gz"
snapshot_cask_asset="UpdateBar-${snapshot_version}-macos-arm64.app.tar.gz"
snapshot_sha="0000000000000000000000000000000000000000000000000000000000000000"

SNAPSHOT_FORMULA="$TMP_DIR/snapshot-formula.rb"
SNAPSHOT_CASK="$TMP_DIR/snapshot-cask.rb"
cat > "$SNAPSHOT_FORMULA" <<EOF
class Updatebar < Formula
  version "$snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$snapshot_version/$snapshot_formula_asset"
  sha256 "$snapshot_sha"
end
EOF

cat > "$SNAPSHOT_CASK" <<EOF
cask "updatebar-app" do
  version "$snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/$snapshot_cask_asset"
  sha256 "$snapshot_sha"
end
EOF

SNAPSHOT_OUTPUT="$TMP_DIR/snapshot.out"
if UPDATEBAR_VERIFY_STATIC_ONLY=1 \
  UPDATEBAR_HOMEBREW_FORMULA_PATH="$SNAPSHOT_FORMULA" \
  UPDATEBAR_HOMEBREW_CASK_PATH="$SNAPSHOT_CASK" \
  bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$SNAPSHOT_OUTPUT" 2>&1; then
  snapshot_status=0
else
  snapshot_status=$?
fi

if [[ "$snapshot_status" -ne 0 ]]; then
  echo "static-only metadata verification rejected the older published snapshot" >&2
  cat "$SNAPSHOT_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "release metadata verification passed for version $snapshot_version" "$SNAPSHOT_OUTPUT"; then
  echo "static-only metadata verification did not accept the older published snapshot" >&2
  cat "$SNAPSHOT_OUTPUT" >&2
  exit 1
fi

run_snapshot_rejection() {
  local label="$1"
  local formula_path="$2"
  local cask_path="$3"
  local expected_error="$4"
  local output="$TMP_DIR/$label.out"
  local status

  if UPDATEBAR_VERIFY_STATIC_ONLY=1 \
    UPDATEBAR_HOMEBREW_FORMULA_PATH="$formula_path" \
    UPDATEBAR_HOMEBREW_CASK_PATH="$cask_path" \
    bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" > "$output" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    echo "snapshot metadata accepted invalid $label" >&2
    cat "$output" >&2
    exit 1
  fi

  if ! grep -Fq "$expected_error" "$output"; then
    echo "invalid snapshot metadata $label did not report the expected error" >&2
    cat "$output" >&2
    exit 1
  fi
}

MISMATCHED_CASK="$TMP_DIR/mismatched-cask.rb"
cat > "$MISMATCHED_CASK" <<EOF
cask "updatebar-app" do
  version "0.6.1"
  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/UpdateBar-#{version}-macos-arm64.app.tar.gz"
  sha256 "$snapshot_sha"
end
EOF
run_snapshot_rejection "mismatched-versions" "$SNAPSHOT_FORMULA" "$MISMATCHED_CASK" \
  "cask version (0.6.1) does not match formula version ($snapshot_version)"

MALFORMED_FORMULA="$TMP_DIR/malformed-formula.rb"
cat > "$MALFORMED_FORMULA" <<EOF
class Updatebar < Formula
  version "$snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$snapshot_version/$snapshot_formula_asset"
  sha256 "not-a-sha"
end
EOF
run_snapshot_rejection "malformed-formula-sha" "$MALFORMED_FORMULA" "$SNAPSHOT_CASK" \
  "formula sha256 is not a 64-character lowercase hex value"

MALFORMED_CASK="$TMP_DIR/malformed-cask.rb"
cat > "$MALFORMED_CASK" <<EOF
cask "updatebar-app" do
  version "$snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/$snapshot_cask_asset"
  sha256 "not-a-sha"
end
EOF
run_snapshot_rejection "malformed-cask-sha" "$SNAPSHOT_FORMULA" "$MALFORMED_CASK" \
  "cask sha256 is not a 64-character lowercase hex value"

WRONG_FORMULA_REPOSITORY="$TMP_DIR/wrong-formula-repository.rb"
cat > "$WRONG_FORMULA_REPOSITORY" <<EOF
class Updatebar < Formula
  version "$snapshot_version"
  url "https://example.test/releases/download/v$snapshot_version/$snapshot_formula_asset"
  sha256 "$snapshot_sha"
end
EOF
run_snapshot_rejection "wrong-formula-repository" "$WRONG_FORMULA_REPOSITORY" "$SNAPSHOT_CASK" \
  "formula URL must use https://github.com/sonim1/UpdateBar/releases/download/v$snapshot_version/"

WRONG_CASK_REPOSITORY="$TMP_DIR/wrong-cask-repository.rb"
cat > "$WRONG_CASK_REPOSITORY" <<EOF
cask "updatebar-app" do
  version "$snapshot_version"
  url "https://example.test/releases/download/v#{version}/$snapshot_cask_asset"
  sha256 "$snapshot_sha"
end
EOF
run_snapshot_rejection "wrong-cask-repository" "$SNAPSHOT_FORMULA" "$WRONG_CASK_REPOSITORY" \
  "cask URL must use https://github.com/sonim1/UpdateBar/releases/download/v$snapshot_version/"

WRONG_FORMULA_ASSET="$TMP_DIR/wrong-formula-asset.rb"
cat > "$WRONG_FORMULA_ASSET" <<EOF
class Updatebar < Formula
  version "$snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$snapshot_version/$snapshot_cask_asset"
  sha256 "$snapshot_sha"
end
EOF
run_snapshot_rejection "wrong-formula-asset" "$WRONG_FORMULA_ASSET" "$SNAPSHOT_CASK" \
  "formula URL must end with $snapshot_formula_asset"

WRONG_CASK_ASSET="$TMP_DIR/wrong-cask-asset.rb"
cat > "$WRONG_CASK_ASSET" <<EOF
cask "updatebar-app" do
  version "$snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/$snapshot_formula_asset"
  sha256 "$snapshot_sha"
end
EOF
run_snapshot_rejection "wrong-cask-asset" "$SNAPSHOT_FORMULA" "$WRONG_CASK_ASSET" \
  "cask URL must end with $snapshot_cask_asset"

cat > "$TMP_DIR/bad-formula.rb" <<EOF
class Updatebar < Formula
  version "$published_snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$published_snapshot_version/$published_formula_asset"
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
  version "$published_snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$published_snapshot_version/UpdateBar-#{version}-macos-arm64.app.tar.gz"
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
  version "$published_snapshot_version"
  url "https://example.test/releases/v$published_snapshot_version/$published_formula_asset"
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

if ! grep -Fq "formula URL must use https://github.com/sonim1/UpdateBar/releases/download/v$published_snapshot_version/" "$BAD_URL_OUTPUT"; then
  echo "invalid Homebrew formula release URL did not report the expected error" >&2
  cat "$BAD_URL_OUTPUT" >&2
  exit 1
fi

cat > "$TMP_DIR/bad-cask-url.rb" <<EOF
cask "updatebar-app" do
  version "$published_snapshot_version"
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

if ! grep -Fq "cask URL must use https://github.com/sonim1/UpdateBar/releases/download/v$published_snapshot_version/" "$BAD_CASK_URL_OUTPUT"; then
  echo "invalid Homebrew cask release URL did not report the expected error" >&2
  cat "$BAD_CASK_URL_OUTPUT" >&2
  exit 1
fi

cat > "$TMP_DIR/bad-formula-asset.rb" <<EOF
class Updatebar < Formula
  version "$published_snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$published_snapshot_version/$published_cask_asset"
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

if ! grep -Fq "formula URL must end with $published_formula_asset" "$BAD_FORMULA_ASSET_OUTPUT"; then
  echo "invalid Homebrew formula asset name did not report the expected error" >&2
  cat "$BAD_FORMULA_ASSET_OUTPUT" >&2
  exit 1
fi

cat > "$TMP_DIR/bad-cask-asset.rb" <<EOF
cask "updatebar-app" do
  version "$published_snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/$published_formula_asset"
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

if ! grep -Fq "cask URL must end with $published_cask_asset" "$BAD_CASK_ASSET_OUTPUT"; then
  echo "invalid Homebrew cask asset name did not report the expected error" >&2
  cat "$BAD_CASK_ASSET_OUTPUT" >&2
  exit 1
fi

# The current cask must not move to a DMG until that asset is published.
for rejected_cask_asset in \
  "UpdateBar-#{version}-macos-arm64.dmg" \
  "UpdateBar-#{version}-macos-x86_64.dmg" \
  "UpdateBar-#{version}.dmg"; do
  cat > "$TMP_DIR/rejected-cask.rb" <<EOF
cask "updatebar-app" do
  version "$published_snapshot_version"
  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/$rejected_cask_asset"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF
  set +e
  UPDATEBAR_VERIFY_STATIC_ONLY=1 \
    UPDATEBAR_HOMEBREW_CASK_PATH="$TMP_DIR/rejected-cask.rb" \
    bash Scripts/verify-homebrew-metadata.sh "$TMP_DIR" >/dev/null 2>&1
  rejected_status=$?
  set -e
  if [[ "$rejected_status" -eq 0 ]]; then
    echo "metadata verification accepted noncanonical cask asset: $rejected_cask_asset" >&2
    exit 1
  fi
done

# Strict mode with real (mismatching) archives must fail on SHA equality...
CANDIDATE_FORMULA="$TMP_DIR/candidate-formula.rb"
CANDIDATE_CASK="$TMP_DIR/candidate-cask.rb"
cat > "$CANDIDATE_FORMULA" <<EOF
class Updatebar < Formula
  version "$UPDATEBAR_VERSION"
  url "https://github.com/sonim1/UpdateBar/releases/download/v$UPDATEBAR_VERSION/$formula_asset"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF
cat > "$CANDIDATE_CASK" <<EOF
cask "updatebar-app" do
  version "$UPDATEBAR_VERSION"
  url "https://github.com/sonim1/UpdateBar/releases/download/v#{version}/$cask_asset"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF

STRICT_OUTPUT="$TMP_DIR/strict.out"
set +e
UPDATEBAR_VERIFY_STRICT=1 \
UPDATEBAR_HOMEBREW_FORMULA_PATH="$CANDIDATE_FORMULA" \
UPDATEBAR_HOMEBREW_CASK_PATH="$CANDIDATE_CASK" \
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
UPDATEBAR_HOMEBREW_FORMULA_PATH="$CANDIDATE_FORMULA" \
UPDATEBAR_HOMEBREW_CASK_PATH="$CANDIDATE_CASK" \
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
UPDATEBAR_HOMEBREW_FORMULA_PATH="$CANDIDATE_FORMULA" \
UPDATEBAR_HOMEBREW_CASK_PATH="$CANDIDATE_CASK" \
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
