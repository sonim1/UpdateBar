#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
export UPDATEBAR_HOME="$TMP_HOME"

RUNNER=( "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-updatebar.sh" )

run_updatebar() {
  local args=("$@")
  "${RUNNER[@]}" "${args[@]}"
}

run_updatebar version --json >/dev/null
run_updatebar schema >/dev/null
run_updatebar validate Fixtures/manifests/valid-basic.json --json >/dev/null
run_updatebar validate - --json < Fixtures/manifests/valid-basic.json >/dev/null
run_updatebar import Fixtures/manifests/untrusted-import.json --json >/dev/null
run_updatebar list --json >/dev/null
run_updatebar status --json --exit-zero-on-outdated >/dev/null
run_updatebar guide agent >/dev/null
run_updatebar guide recipe >/dev/null
run_updatebar template recipe --kind npm --id smoke-tool --source smoke-tool >/dev/null
run_updatebar template manifest --kind npm --id smoke-tool --source smoke-tool >/dev/null
run_updatebar --generate-completion-script bash >/dev/null

echo "smoke ok"
