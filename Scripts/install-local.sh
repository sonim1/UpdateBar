#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
SWIFT_BIN="${SWIFT_BIN:-swift}"

"$SWIFT_BIN" build -c release --product updatebar
mkdir -p "$PREFIX/bin"
cp .build/release/updatebar "$PREFIX/bin/updatebar"
chmod 0755 "$PREFIX/bin/updatebar"

echo "installed $PREFIX/bin/updatebar"
