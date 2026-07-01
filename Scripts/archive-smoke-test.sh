#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"
ARCHIVE="${1:-}"

if [[ -z "$ARCHIVE" ]]; then
  ARCHIVE="$("$ROOT/Scripts/build-release.sh" | tail -n 1)"
fi

if [[ -f "${ARCHIVE}.sha256" ]]; then
  "$ROOT/Scripts/verify-archive-checksum.sh" "$ARCHIVE"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR"
BIN="$TMP_DIR/updatebar"
HOME_DIR="$TMP_DIR/home"
mkdir -p "$HOME_DIR"

CLI_VERSION="$(UPDATEBAR_HOME="$HOME_DIR" "$BIN" --version)"
if [[ "$CLI_VERSION" != "$UPDATEBAR_VERSION" ]]; then
  echo "archive CLI version mismatch for $ARCHIVE" >&2
  echo "  expected: $UPDATEBAR_VERSION" >&2
  echo "  actual:   $CLI_VERSION" >&2
  exit 1
fi
UPDATEBAR_HOME="$HOME_DIR" "$BIN" schema >/dev/null
UPDATEBAR_HOME="$HOME_DIR" "$BIN" guide agent >/dev/null
UPDATEBAR_HOME="$HOME_DIR" "$BIN" guide recipe >/dev/null
UPDATEBAR_HOME="$HOME_DIR" "$BIN" template recipe --kind npm --id archive-tool --source archive-tool >/dev/null

if [[ "$(uname -s)" == "Darwin" ]]; then
  HOME="$TMP_DIR/user" UPDATEBAR_HOME="$HOME_DIR" "$BIN" background status --json >/dev/null
  HOME="$TMP_DIR/user" UPDATEBAR_HOME="$HOME_DIR" "$BIN" background install --yes --json >/dev/null
  HOME="$TMP_DIR/user" UPDATEBAR_HOME="$HOME_DIR" "$BIN" background uninstall --json >/dev/null
fi

echo "archive smoke ok"
