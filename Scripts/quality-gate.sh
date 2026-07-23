#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SWIFT_BIN="${SWIFT_BIN:-swift}"
SKIP_MENUBAR_SMOKE="${SKIP_MENUBAR_SMOKE:-0}"
RELEASE_SYNTAX_SCRIPTS=(
  "Scripts/setup-update-hosting.sh"
  "Scripts/generate-appcast.sh"
  "Scripts/publish-update.sh"
  "Scripts/generate-release-manifest.sh"
  "Scripts/publish-release.sh"
  "Scripts/dispatch-homebrew-update.sh"
  "Scripts/build-release.sh"
  "Scripts/package-app.sh"
  "Scripts/build-app-icon.sh"
  "Scripts/build-app-dmg.sh"
  "Scripts/app-dmg-smoke-test.sh"
)
SKIP_TUI_SMOKE="${SKIP_TUI_SMOKE:-0}"
SKIP_TUI_INPUT="${SKIP_TUI_INPUT:-0}"
SKIP_TUI_SMOKE="${SKIP_TUI_SMOKE:-0}"
SKIP_TUI_INPUT="${SKIP_TUI_INPUT:-0}"

if [[ "$(uname -s)" == "Darwin" && -z "${DEVELOPER_DIR:-}" ]]; then
  XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  XCODE_XCTEST="$XCODE_DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"
  if [[ -d "$XCODE_XCTEST" ]]; then
    export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
  fi
fi

require_swift_xctest() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return
  fi

  local developer_dir="${DEVELOPER_DIR:-}"
  if [[ -z "$developer_dir" ]] && command -v xcode-select >/dev/null 2>&1; then
    developer_dir="$(xcode-select -p 2>/dev/null || true)"
  fi

  local xctest_path=""
  if [[ -n "$developer_dir" ]]; then
    xctest_path="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"
  fi

  if [[ -z "$xctest_path" || ! -d "$xctest_path" ]]; then
    echo "Swift XCTest not found at ${xctest_path:-<unknown>}" >&2
    echo "Selected developer directory: ${developer_dir:-<none>}" >&2
    echo "Install full Xcode or set DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer before running Scripts/quality-gate.sh." >&2
    exit 1
  fi
}

echo "running script syntax checks"
bash Scripts/script-syntax-test.sh
bash -n "${RELEASE_SYNTAX_SCRIPTS[@]}"

echo "running quality gate contract checks"
bash Scripts/quality-gate-contract-test.sh

echo "running locked release tooling checks"
bash Scripts/release-tooling-test.sh

echo "running update hosting setup checks"
bash Scripts/setup-update-hosting-test.sh

echo "running signed appcast checks"
bash Scripts/generate-appcast-test.sh

echo "running update publication checks"
bash Scripts/publish-update-test.sh

echo "running release manifest checks"
bash Scripts/generate-release-manifest-test.sh

echo "running release publication checks"
bash Scripts/publish-release-test.sh

echo "running Homebrew tap dispatch checks"
bash Scripts/dispatch-homebrew-update-test.sh

echo "running protected release workflow checks"
bash Scripts/release-workflow-test.sh

SWIFT_FORMAT_COMMAND=()
if command -v swift-format >/dev/null 2>&1; then
  SWIFT_FORMAT_COMMAND=(swift-format)
elif command -v xcrun >/dev/null 2>&1 && xcrun --find swift-format >/dev/null 2>&1; then
  SWIFT_FORMAT_COMMAND=(xcrun swift-format)
elif "$SWIFT_BIN" format --version >/dev/null 2>&1; then
  SWIFT_FORMAT_COMMAND=("$SWIFT_BIN" format)
else
  echo "swift-format is required for quality gate checks" >&2
  exit 1
fi
echo "running Swift format checks"
"${SWIFT_FORMAT_COMMAND[@]}" lint --strict --recursive Sources Tests Package.swift

if command -v shellcheck >/dev/null 2>&1; then
  echo "running script quality checks"
  shellcheck --severity=warning Scripts/*.sh
else
  echo "shellcheck not installed; skipping script quality checks"
fi

echo "checking Swift XCTest availability"
require_swift_xctest

echo "building debug updatebar CLI for CLI tests"
"$SWIFT_BIN" build --product updatebar
export UPDATEBAR_TEST_BIN="$ROOT/.build/debug/updatebar"

echo "running swift unit tests"
"$SWIFT_BIN" test
export UPDATEBAR_BIN="$ROOT/.build/debug/updatebar"

echo "running updatebar smoke test"
bash Scripts/smoke-test.sh

echo "running installed CLI smoke test"
bash Scripts/cli-smoke-test.sh

echo "running updatebar edgecase checks"
bash Scripts/e2e-edgecases.sh

echo "running local install smoke test"
bash Scripts/install-local-smoke-test.sh

echo "running release tar args check"
bash Scripts/release-tar-args-test.sh

echo "running changelog extraction check"
bash Scripts/extract-changelog-section-test.sh

echo "running archive checksum verification behavior check"
bash Scripts/verify-archive-checksum-test.sh

echo "running release archive behavior check"
bash Scripts/build-release-archive-test.sh

echo "running app icon asset check"
bash Scripts/app-icon-test.sh

echo "running app DMG behavior check"
bash Scripts/build-app-dmg-test.sh

echo "running app signing behavior check"
bash Scripts/package-app-signing-test.sh

echo "running archive smoke test"
bash Scripts/archive-smoke-test.sh

echo "running install release smoke test"
bash Scripts/install-release-smoke-test.sh

echo "running homebrew packaging check"
bash Scripts/homebrew-packaging-test.sh

echo "running homebrew metadata check"
UPDATEBAR_VERIFY_STATIC_ONLY=1 bash Scripts/verify-homebrew-metadata.sh

echo "running homebrew metadata behavior check"
bash Scripts/verify-homebrew-metadata-test.sh

if [[ "$SKIP_TUI_SMOKE" != "1" ]]; then
  if command -v npm >/dev/null 2>&1; then
    echo "running tui smoke test"
    bash Scripts/tui-smoke-test.sh
  else
    echo "skipping tui smoke test (npm not found)"
  fi
else
  echo "skipping tui smoke test (SKIP_TUI_SMOKE)"
fi

if [[ "$SKIP_TUI_INPUT" != "1" ]]; then
  if command -v npm >/dev/null 2>&1; then
    echo "running tui input regression test"
    bash Scripts/tui-input-test.sh
  else
    echo "skipping tui input regression test (npm not found)"
  fi
else
  echo "skipping tui input regression test (SKIP_TUI_INPUT)"
fi

if [[ "$SKIP_MENUBAR_SMOKE" != "1" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "packaging menu bar app"
    QUALITY_GATE_SPARKLE_KEY="MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="
    SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-$QUALITY_GATE_SPARKLE_KEY}" \
      UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 bash Scripts/package-app.sh >/dev/null
    echo "running menubar smoke test"
    bash Scripts/menubar-smoke-test.sh dist/UpdateBar.app
  else
    echo "skipping menubar smoke on non-macOS"
  fi
fi

echo "quality gate complete"
