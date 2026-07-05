#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == "--help" ]]; then
  printf '%s\n' \
    "Usage: Scripts/install-release.sh [tag]" \
    "" \
    "Download and install the prebuilt UpdateBar CLI archive from GitHub releases." \
    "" \
    "Arguments:" \
    "  [tag]   Release tag to install, e.g. v0.2.0. Defaults to latest." \
    "" \
    "Environment:" \
    "  UPDATEBAR_INSTALL_PREFIX   Directory to install updatebar into." \
    '                           Defaults to "$HOME/.local/bin".' \
    "  UPDATEBAR_GITHUB_REPO      GitHub repo in owner/name form." \
    '                            Defaults to "sonim1/UpdateBar".'
  exit 0
fi

for tool in awk curl grep gzip install mkdir mktemp rm tar uname; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required to install release assets" >&2
    exit 1
  fi
done

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

if ! curl -fsSL "$RELEASE_URL" > "$RELEASE_JSON"; then
  echo "Failed to fetch GitHub release metadata: $RELEASE_URL" >&2
  exit 1
fi

RELEASE_ERROR_MESSAGE="$(awk -F'"' '$2 == "message" { print $4; exit }' "$RELEASE_JSON")"
if [[ -n "$RELEASE_ERROR_MESSAGE" ]] && ! grep -Fq '"browser_download_url"' "$RELEASE_JSON"; then
  echo "GitHub release lookup failed for $RELEASE_URL: $RELEASE_ERROR_MESSAGE" >&2
  exit 1
fi

ASSET_URL=$(awk -F'"' -v platform="$PLATFORM" -v arch="$ARCH" \
  '$2=="browser_download_url" && $4 ~ "/updatebar-[0-9][^\\\"]*-" platform "-" arch "\\.tar\\.gz$" { print $4; exit }' \
  "$RELEASE_JSON")

ASSET_SHA_URL="${ASSET_URL}.sha256"
if [[ -z "$ASSET_URL" ]]; then
  echo "No prebuilt UpdateBar archive found for ${PLATFORM}/${ARCH} in $RELEASE_URL" >&2
  echo "Available updatebar assets in ${RELEASE_PATH} are:" >&2
  awk -F'"' '$2=="browser_download_url" && $4 ~ "/updatebar-[0-9][^\\\"]*\\.tar\\.gz$" { print $4 }' \
    "$RELEASE_JSON" >&2
  echo "No matching prebuilt asset is published for this platform. Build from source instead:" >&2
  echo "  swift build -c release --product updatebar" >&2
  exit 1
fi

ARCHIVE_NAME="${ASSET_URL##*/}"
ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE_NAME}"

if ! curl -fsSL -o "$ARCHIVE_PATH" "$ASSET_URL"; then
  echo "Failed to download release archive: $ASSET_URL" >&2
  exit 1
fi
if ! curl -fsSL -o "${ARCHIVE_PATH}.sha256" "$ASSET_SHA_URL"; then
  echo "Failed to download release checksum: $ASSET_SHA_URL" >&2
  exit 1
fi

EXPECTED_SHA="$(awk 'NF > 0 { print $1; exit }' "${ARCHIVE_PATH}.sha256")"
if [[ -z "$EXPECTED_SHA" ]]; then
  echo "Failed to parse SHA from ${ARCHIVE_PATH}.sha256" >&2
  exit 1
fi
if [[ ! "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]]; then
  echo "release checksum file did not contain a 64-character lowercase hex SHA: ${ARCHIVE_PATH}.sha256" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA="$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')"
else
  echo "shasum or sha256sum is required to verify release archive checksums" >&2
  exit 1
fi

if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "SHA mismatch for ${ARCHIVE_NAME}" >&2
  echo "  expected: $EXPECTED_SHA" >&2
  echo "  actual:   $ACTUAL_SHA" >&2
  exit 1
fi

if ! tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"; then
  echo "Failed to extract release archive: $ARCHIVE_NAME" >&2
  exit 1
fi
if [[ ! -x "${TMP_DIR}/updatebar" ]]; then
  echo "release archive did not contain executable updatebar: ${ARCHIVE_NAME}" >&2
  exit 1
fi

mkdir -p "$PREFIX"
install -m 755 "${TMP_DIR}/updatebar" "${PREFIX}/updatebar"

printf '%s\n' \
  "Installed updatebar to ${PREFIX}/updatebar" \
  "Make sure this directory is on your PATH:" \
  "  export PATH=\"${PREFIX}:\$PATH\""
