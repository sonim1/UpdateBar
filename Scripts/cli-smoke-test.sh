#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
export UPDATEBAR_HOME="$TMP_HOME"

if [[ -n "${UPDATEBAR_BIN:-}" ]]; then
    RUNNER=("$UPDATEBAR_BIN")
elif command -v updatebar >/dev/null 2>&1; then
    RUNNER=("$(command -v updatebar)")
else
    RUNNER=("$ROOT/Scripts/run-updatebar.sh")
fi

"${RUNNER[@]}" --version >/dev/null
"${RUNNER[@]}" doctor >/dev/null
"${RUNNER[@]}" scan >/dev/null
"${RUNNER[@]}" status --json --exit-zero-on-outdated >/dev/null

echo "cli smoke ok: ${RUNNER[*]}"
