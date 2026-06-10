#!/usr/bin/env bash
set -euo pipefail

source version.env

SWIFT_BIN="${SWIFT_BIN:-swift}"
VERSION="${UPDATEBAR_VERSION:?UPDATEBAR_VERSION is required}"
"$(dirname "$0")/generate-version-source.sh"

case "$(uname -s)" in
  Darwin) PLATFORM="macos" ;;
  Linux) PLATFORM="linux" ;;
  *) echo "unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64) ARCH="x86_64" ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

"$SWIFT_BIN" build -c release --product updatebar

rm -rf dist
mkdir -p "dist/stage/updatebar-${VERSION}"
cp .build/release/updatebar "dist/stage/updatebar-${VERSION}/updatebar"
chmod 0755 "dist/stage/updatebar-${VERSION}/updatebar"

if [[ "$PLATFORM" == "macos" ]] && command -v codesign >/dev/null 2>&1; then
  codesign -s - "dist/stage/updatebar-${VERSION}/updatebar" >/dev/null 2>&1 || true
fi

ARCHIVE="dist/updatebar-${VERSION}-${PLATFORM}-${ARCH}.tar.gz"
tar -C "dist/stage/updatebar-${VERSION}" -czf "$ARCHIVE" updatebar

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$ARCHIVE" >"${ARCHIVE}.sha256"
else
  sha256sum "$ARCHIVE" >"${ARCHIVE}.sha256"
fi

echo "$ARCHIVE"
