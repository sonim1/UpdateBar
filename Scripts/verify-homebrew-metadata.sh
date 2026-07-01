#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${1-}" == "--help" ]]; then
  cat <<'EOF'
Usage: Scripts/verify-homebrew-metadata.sh [dist_dir]

Verify release metadata consistency between built assets and Homebrew files.

Arguments:
  [dist_dir]   Directory containing release artifacts (default: dist)
EOF
  exit 0
fi

source version.env

DIST_DIR="${1:-dist}"
FORMULA_PATH="Packaging/homebrew/updatebar.rb"
CASK_PATH="Packaging/homebrew/Casks/updatebar-app.rb"
STRICT="${UPDATEBAR_VERIFY_STRICT:-0}"

hash_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    echo "shasum or sha256sum is required" >&2
    exit 1
  fi
}

FORMULA_VERSION="$(awk '$1 == "version" { gsub(/"/, "", $2); print $2; exit }' "$FORMULA_PATH")"
FORMULA_URL="$(awk '$1 == "url" { gsub(/"/, "", $2); print $2; exit }' "$FORMULA_PATH")"
FORMULA_SHA="$(awk '$1 == "sha256" { gsub(/"/, "", $2); print $2; exit }' "$FORMULA_PATH")"

if [[ "$FORMULA_VERSION" != "$UPDATEBAR_VERSION" ]]; then
  echo "formula version ($FORMULA_VERSION) does not match version.env ($UPDATEBAR_VERSION)" >&2
  exit 1
fi

FORMULA_ASSET="$(basename "$FORMULA_URL")"
FORMULA_SHA_FILE="$DIST_DIR/$FORMULA_ASSET.sha256"
FORMULA_ARCHIVE="$DIST_DIR/$FORMULA_ASSET"
if [[ ! -f "$FORMULA_ARCHIVE" ]]; then
  if [[ "$STRICT" == "1" ]]; then
    echo "missing CLI archive for formula check: $FORMULA_ARCHIVE" >&2
    exit 1
  fi
  echo "skip CLI formula verification; asset not found: $FORMULA_ASSET" >&2
  FORMULA_VERIFIED=0
else
  FORMULA_VERIFIED=1
fi
if [[ "$FORMULA_VERIFIED" -eq 1 && ! -f "$FORMULA_SHA_FILE" ]]; then
  echo "missing CLI archive checksum: $FORMULA_SHA_FILE" >&2
  exit 1
fi
if [[ "$FORMULA_VERIFIED" -eq 1 ]]; then
  FORMULA_CALC_SHA="$(hash_file "$FORMULA_ARCHIVE")"
  FORMULA_RECORDED_SHA="$(awk '{print $1}' "$FORMULA_SHA_FILE")"

  if [[ "$FORMULA_CALC_SHA" != "$FORMULA_RECORDED_SHA" ]]; then
    if [[ "$STRICT" == "1" ]]; then
      echo "CLI archive checksum mismatch for $FORMULA_ARCHIVE" >&2
      echo "  recorded: $FORMULA_RECORDED_SHA" >&2
      echo "  calc:     $FORMULA_CALC_SHA" >&2
      exit 1
    fi
    echo "warning: CLI archive checksum mismatch (non-strict): recorded $FORMULA_RECORDED_SHA vs calc $FORMULA_CALC_SHA" >&2
  fi
  if [[ "$FORMULA_SHA" != "$FORMULA_RECORDED_SHA" ]]; then
    if [[ "$STRICT" == "1" ]]; then
      echo "formula SHA mismatch for updatebar.rb" >&2
      echo "  formula: $FORMULA_SHA" >&2
      echo "  archive: $FORMULA_RECORDED_SHA" >&2
      exit 1
    fi
    echo "warning: formula SHA mismatch (non-strict): updatebar.rb has $FORMULA_SHA, archive $FORMULA_RECORDED_SHA" >&2
  fi
fi

if [[ ! -f "$CASK_PATH" ]]; then
  echo "missing cask file: $CASK_PATH" >&2
  exit 1
fi

CASK_VERSION="$(awk '$1 == "version" { gsub(/"/, "", $2); print $2; exit }' "$CASK_PATH")"
CASK_URL="$(awk '$1 == "url" { gsub(/"/, "", $2); print $2; exit }' "$CASK_PATH")"
CASK_SHA="$(awk '$1 == "sha256" { gsub(/"/, "", $2); print $2; exit }' "$CASK_PATH")"

if [[ "$CASK_VERSION" != "$UPDATEBAR_VERSION" ]]; then
  echo "cask version ($CASK_VERSION) does not match version.env ($UPDATEBAR_VERSION)" >&2
  exit 1
fi

CASK_ASSET="$(basename "$CASK_URL")"
CASK_ASSET="${CASK_ASSET/\#\{version\}/$CASK_VERSION}"
CASK_ARCHIVE="$DIST_DIR/$CASK_ASSET"
CASK_SHA_FILE="$DIST_DIR/$CASK_ASSET.sha256"

if [[ -f "$CASK_ARCHIVE" ]]; then
  if [[ ! -f "$CASK_SHA_FILE" ]]; then
    echo "missing app archive checksum: $CASK_SHA_FILE" >&2
    exit 1
  fi

  CASK_CALC_SHA="$(hash_file "$CASK_ARCHIVE")"
  CASK_RECORDED_SHA="$(awk '{print $1}' "$CASK_SHA_FILE")"

  if [[ "$CASK_CALC_SHA" != "$CASK_RECORDED_SHA" ]]; then
    if [[ "$STRICT" == "1" ]]; then
      echo "app archive checksum mismatch for $CASK_ARCHIVE" >&2
      echo "  recorded: $CASK_RECORDED_SHA" >&2
      echo "  calc:     $CASK_CALC_SHA" >&2
      exit 1
    fi
    echo "warning: app archive checksum mismatch (non-strict): recorded $CASK_RECORDED_SHA vs calc $CASK_CALC_SHA" >&2
  fi
  if [[ "$CASK_SHA" != "$CASK_RECORDED_SHA" ]]; then
    if [[ "$STRICT" == "1" ]]; then
      echo "cask SHA mismatch for updatebar-app.rb" >&2
      echo "  cask: $CASK_SHA" >&2
      echo "  archive: $CASK_RECORDED_SHA" >&2
      exit 1
    fi
    echo "warning: cask SHA mismatch (non-strict): updatebar-app.rb has $CASK_SHA, archive $CASK_RECORDED_SHA" >&2
  fi
else
  if [[ "$STRICT" == "1" ]]; then
    echo "missing app archive for cask verification: $CASK_ARCHIVE" >&2
    exit 1
  fi
  echo "skip cask verification; asset not found: $CASK_ASSET" >&2
fi

echo "release metadata verification passed for version $UPDATEBAR_VERSION"
