#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/version.env"

SWIFT_BIN="${SWIFT_BIN:-swift}"
VERSION="${UPDATEBAR_VERSION:?UPDATEBAR_VERSION is required}"
"$ROOT/Scripts/generate-version-source.sh"

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

BUILD_ROOT="$(pwd -P)"
"$SWIFT_BIN" build -c release --product updatebar \
  -Xswiftc -debug-prefix-map -Xswiftc "${BUILD_ROOT}=." \
  -Xswiftc -file-prefix-map -Xswiftc "${BUILD_ROOT}=."

rm -rf dist
mkdir -p "dist/stage/updatebar-${VERSION}"
cp .build/release/updatebar "dist/stage/updatebar-${VERSION}/updatebar"
chmod 0755 "dist/stage/updatebar-${VERSION}/updatebar"

if [[ "${UPDATEBAR_STRIP_BINARY:-0}" == "1" ]]; then
  if command -v strip >/dev/null 2>&1; then
    # Stripping this binary removes required load commands on current Swift toolchains.
    # Keep release artifacts runnable by default; set UPDATEBAR_STRIP_BINARY=1 only
    # when you have a validated stripping workflow for your platform.
    strip -S -x "dist/stage/updatebar-${VERSION}/updatebar" >/dev/null 2>&1 || true
  fi
fi

if [[ "${UPDATEBAR_AD_HOC_CODESIGN:-0}" == "1" ]] && [[ "$PLATFORM" == "macos" ]] && command -v codesign >/dev/null 2>&1; then
  codesign -s - "dist/stage/updatebar-${VERSION}/updatebar" >/dev/null 2>&1 || true
fi

touch -t 202001010000 "dist/stage/updatebar-${VERSION}/updatebar"

ARCHIVE="dist/updatebar-${VERSION}-${PLATFORM}-${ARCH}.tar.gz"
TAR_ARGS=()
while IFS= read -r arg; do
  TAR_ARGS+=("$arg")
done < <("$ROOT/Scripts/release-tar-args.sh" tar)
COPYFILE_DISABLE=1 tar "${TAR_ARGS[@]}" -C "dist/stage/updatebar-${VERSION}" \
  -cf - updatebar | gzip -n >"$ARCHIVE"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$ARCHIVE" >"${ARCHIVE}.sha256"
else
  sha256sum "$ARCHIVE" >"${ARCHIVE}.sha256"
fi

echo "$ROOT/$ARCHIVE"
