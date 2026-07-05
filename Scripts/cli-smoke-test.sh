#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
export UPDATEBAR_HOME="$TMP_HOME"

RUNNER=("$ROOT/Scripts/run-updatebar.sh")

"${RUNNER[@]}" --version >/dev/null
"${RUNNER[@]}" doctor >/dev/null
"${RUNNER[@]}" scan >/dev/null
"${RUNNER[@]}" status --json --exit-zero-on-outdated >/dev/null

echo "cli smoke ok"
