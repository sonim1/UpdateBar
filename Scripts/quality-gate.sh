#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SWIFT_BIN="${SWIFT_BIN:-swift}"
SKIP_MENUBAR_SMOKE="${SKIP_MENUBAR_SMOKE:-0}"

if [[ "$(uname -s)" == "Darwin" && -z "${DEVELOPER_DIR:-}" ]]; then
  XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  XCODE_XCTEST="$XCODE_DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"
  if [[ -d "$XCODE_XCTEST" ]]; then
    export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
  fi
fi

if [[ -z "${UPDATEBAR_BIN:-}" && -x .build/debug/updatebar ]]; then
  export UPDATEBAR_BIN="$ROOT/.build/debug/updatebar"
fi
if command -v shellcheck >/dev/null 2>&1; then
  echo "running script quality checks"
  shellcheck Scripts/*.sh
else
  echo "shellcheck not installed; skipping script quality checks"
fi

echo "running swift unit tests"
"$SWIFT_BIN" test

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
