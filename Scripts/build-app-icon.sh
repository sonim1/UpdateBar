#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Assets/AppIcon/UpdateBar.svg"
OUTPUT="$ROOT/Assets/AppIcon/UpdateBar.icns"

for tool in sips iconutil; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool is required to build the macOS app icon" >&2
    exit 1
  }
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
MASTER="$TMP_DIR/UpdateBar.png"
ICONSET="$TMP_DIR/UpdateBar.iconset"
mkdir -p "$ICONSET"

sips -s format png "$SOURCE" --out "$MASTER" >/dev/null

while read -r points scale filename; do
  pixels=$((points * scale))
  sips -z "$pixels" "$pixels" "$MASTER" --out "$ICONSET/$filename" >/dev/null
done <<'SIZES'
16 1 icon_16x16.png
16 2 icon_16x16@2x.png
32 1 icon_32x32.png
32 2 icon_32x32@2x.png
128 1 icon_128x128.png
128 2 icon_128x128@2x.png
256 1 icon_256x256.png
256 2 icon_256x256@2x.png
512 1 icon_512x512.png
512 2 icon_512x512@2x.png
SIZES

iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "$OUTPUT"
