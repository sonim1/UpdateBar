#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_MENUBAR_SMOKE="${SKIP_MENUBAR_SMOKE:-0}"
if [[ -z "${UPDATEBAR_BIN:-}" && -x .build/debug/updatebar ]]; then
  export UPDATEBAR_BIN="$ROOT/.build/debug/updatebar"
fi

echo "running updatebar smoke test"
bash Scripts/smoke-test.sh

echo "running updatebar edgecase checks"
bash Scripts/e2e-edgecases.sh

echo "running release tar args check"
bash Scripts/release-tar-args-test.sh

echo "running homebrew packaging check"
bash Scripts/homebrew-packaging-test.sh

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "running tui smoke test"
  bash Scripts/tui-smoke-test.sh
else
  echo "skipping tui smoke test on non-macOS"
fi

if [[ "$SKIP_MENUBAR_SMOKE" != "1" ]]; then
  if [[ "$(uname -s)" == "Darwin" && -x dist/UpdateBar.app/Contents/MacOS/UpdateBar ]]; then
    echo "running menubar smoke test"
    bash Scripts/menubar-smoke-test.sh dist/UpdateBar.app
  else
    echo "skipping menubar smoke (app not packaged)"
  fi
fi

echo "quality gate complete"
