#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/Assets/AppIcon/UpdateBar.svg"
ICNS="$ROOT/Assets/AppIcon/UpdateBar.icns"

[[ -f "$SVG" ]] || { echo "missing app icon SVG: $SVG" >&2; exit 1; }
[[ -f "$ICNS" ]] || { echo "missing app icon ICNS: $ICNS" >&2; exit 1; }

grep -Fq 'viewBox="0 0 1024 1024"' "$SVG" || {
  echo "app icon SVG must use a 1024x1024 viewBox" >&2
  exit 1
}
for layer in 'id="background"' 'id="arrow"' 'id="bar"'; do
  grep -Fq "$layer" "$SVG" || {
    echo "app icon SVG missing layer: $layer" >&2
    exit 1
  }
done
if grep -Eq '<text([[:space:]>])' "$SVG"; then
  echo "app icon SVG must not contain text" >&2
  exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  iconutil -c iconset "$ICNS" -o "$TMP_DIR/UpdateBar.iconset"
  for file in \
    icon_16x16.png icon_16x16@2x.png \
    icon_32x32.png icon_32x32@2x.png \
    icon_128x128.png icon_128x128@2x.png \
    icon_256x256.png icon_256x256@2x.png \
    icon_512x512.png icon_512x512@2x.png; do
    [[ -f "$TMP_DIR/UpdateBar.iconset/$file" ]] || {
      echo "app icon ICNS missing representation: $file" >&2
      exit 1
    }
  done
fi

echo "app icon assets ok"
