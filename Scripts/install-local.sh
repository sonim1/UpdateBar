#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${1-}" == "--help" ]]; then
  cat <<'EOF'
Usage: Scripts/install-local.sh

Build and install the local updatebar CLI from source.

Environment:
  UPDATEBAR_INSTALL_PREFIX   Directory to install updatebar into.
                             Defaults to "$HOME/.local/bin".
  PREFIX                     Legacy install prefix root; installs into "$PREFIX/bin".
  SWIFT_BIN                  Swift executable to use. Defaults to "swift".
EOF
  exit 0
fi

if [[ -n "${UPDATEBAR_INSTALL_PREFIX:-}" ]]; then
  INSTALL_DIR="$UPDATEBAR_INSTALL_PREFIX"
elif [[ -n "${PREFIX:-}" ]]; then
  INSTALL_DIR="$PREFIX/bin"
else
  INSTALL_DIR="$HOME/.local/bin"
fi
SWIFT_BIN="${SWIFT_BIN:-swift}"

"$SWIFT_BIN" build -c release --product updatebar
mkdir -p "$INSTALL_DIR"
cp .build/release/updatebar "$INSTALL_DIR/updatebar"
chmod 0755 "$INSTALL_DIR/updatebar"

cat <<EOF
installed $INSTALL_DIR/updatebar
Make sure this directory is on your PATH:
  export PATH="$INSTALL_DIR:\$PATH"
EOF
