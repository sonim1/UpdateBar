#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == "--help" ]]; then
  cat <<'EOF'
Usage: Scripts/install-release.sh [tag]

Download and install the prebuilt UpdateBar CLI archive from GitHub releases.

Arguments:
  [tag]   Release tag to install, e.g. v0.2.0. Defaults to latest.

Environment:
  UPDATEBAR_INSTALL_PREFIX   Directory to install updatebar into.
                            Defaults to "$HOME/.local/bin".
  UPDATEBAR_GITHUB_REPO      GitHub repo in owner/name form.
                            Defaults to "sonim1/UpdateBar".
EOF
  exit 0
fi

REPO="${UPDATEBAR_GITHUB_REPO:-sonim1/UpdateBar}"
PLATFORM=""
ARCH=""

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux) PLATFORM=linux ;;
  *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64) ARCH=x86_64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

RELEASE_PATH="${1:-latest}"
if [[ "$RELEASE_PATH" == "latest" ]]; then
  RELEASE_URL="https://api.github.com/repos/${REPO}/releases/latest"
else
  RELEASE_URL="https://api.github.com/repos/${REPO}/releases/tags/${RELEASE_PATH}"
fi

RELEASE_JSON="$(mktemp)"
TMP_DIR="$(mktemp -d)"
PREFIX="${UPDATEBAR_INSTALL_PREFIX:-$HOME/.local/bin}"

cleanup() {
  rm -f "$RELEASE_JSON"
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

curl -fsSL "$RELEASE_URL" > "$RELEASE_JSON"

ASSET_URL=$(awk -F'"' -v platform="$PLATFORM" -v arch="$ARCH" \
  '$2=="browser_download_url" && $4 ~ "/updatebar-[0-9][^\\\"]*-" platform "-" arch "\\.tar\\.gz$" { print $4; exit }' \
  "$RELEASE_JSON")

ASSET_SHA_URL="${ASSET_URL}.sha256"
if [[ -z "$ASSET_URL" ]]; then
  echo "No prebuilt UpdateBar archive found for ${PLATFORM}/${ARCH} in $RELEASE_URL" >&2
  exit 1
fi

ARCHIVE_NAME="${ASSET_URL##*/}"
ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE_NAME}"

curl -fsSL -o "$ARCHIVE_PATH" "$ASSET_URL"
curl -fsSL -o "${ARCHIVE_PATH}.sha256" "$ASSET_SHA_URL"

EXPECTED_SHA="$(awk '{print $1}' "${ARCHIVE_PATH}.sha256" | head -n 1)"
if [[ -z "$EXPECTED_SHA" ]]; then
  echo "Failed to parse SHA from ${ARCHIVE_PATH}.sha256" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
else
  ACTUAL_SHA="$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')"
fi

if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "SHA mismatch for ${ARCHIVE_NAME}" >&2
  echo "  expected: $EXPECTED_SHA" >&2
  echo "  actual:   $ACTUAL_SHA" >&2
  exit 1
fi

tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"

mkdir -p "$PREFIX"
install -m 755 "${TMP_DIR}/updatebar" "${PREFIX}/updatebar"

cat <<EOF
Installed updatebar to ${PREFIX}/updatebar
Make sure this directory is on your PATH:
  export PATH="${PREFIX}:\$PATH"
EOF
