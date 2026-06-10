#!/usr/bin/env bash
set -euo pipefail

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
export UPDATEBAR_HOME="$TMP_HOME"

SWIFT_BIN="${SWIFT_BIN:-swift}"

"$SWIFT_BIN" run updatebar version --json >/dev/null
"$SWIFT_BIN" run updatebar schema --json >/dev/null
"$SWIFT_BIN" run updatebar validate Fixtures/manifests/valid-basic.json --json >/dev/null
"$SWIFT_BIN" run updatebar validate - --json < Fixtures/manifests/valid-basic.json >/dev/null
"$SWIFT_BIN" run updatebar import Fixtures/manifests/untrusted-import.json --json >/dev/null
"$SWIFT_BIN" run updatebar list --json >/dev/null
"$SWIFT_BIN" run updatebar status --json --exit-zero-on-outdated >/dev/null
"$SWIFT_BIN" run updatebar guide agent >/dev/null
"$SWIFT_BIN" run updatebar guide recipe >/dev/null
"$SWIFT_BIN" run updatebar template recipe --kind npm --id smoke-tool --source smoke-tool >/dev/null
"$SWIFT_BIN" run updatebar template manifest --kind npm --id smoke-tool --source smoke-tool >/dev/null
"$SWIFT_BIN" run updatebar --generate-completion-script bash >/dev/null

echo "smoke ok"
