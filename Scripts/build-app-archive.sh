#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/version.env"

VERSION="${UPDATEBAR_VERSION:?UPDATEBAR_VERSION is required}"
APP_DIR="dist/UpdateBar.app"
ARCHIVE="dist/UpdateBar-${VERSION}-macos-arm64.app.tar.gz"

if [[ ! -d "$APP_DIR" ]]; then
  echo "missing app bundle: $APP_DIR" >&2
  echo "build with: Scripts/package-app.sh" >&2
  exit 1
fi

rm -f "$ARCHIVE" "${ARCHIVE}.sha256"
COPYFILE_DISABLE=1 tar -C dist -cf - UpdateBar.app | gzip -n >"$ARCHIVE"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$ARCHIVE" >"${ARCHIVE}.sha256"
else
  sha256sum "$ARCHIVE" >"${ARCHIVE}.sha256"
fi

echo "$ROOT/$ARCHIVE"
