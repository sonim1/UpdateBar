#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUALITY_GATE="$ROOT/Scripts/quality-gate.sh"
CI_WORKFLOW="$ROOT/.github/workflows/ci.yml"
RELEASE_WORKFLOW="$ROOT/.github/workflows/release.yml"

if [[ ! -f "$CI_WORKFLOW" ]]; then
  echo "ci.yml must exist and run quality-gate.sh" >&2
  exit 1
fi

if ! grep -Fq 'bash Scripts/quality-gate.sh' "$CI_WORKFLOW"; then
  echo "ci.yml must run quality-gate.sh" >&2
  exit 1
fi

if ! grep -Fq 'actions/setup-node' "$CI_WORKFLOW" || ! grep -Fq 'node-version: 20' "$CI_WORKFLOW"; then
  echo "ci.yml must install the TUI Node 20 toolchain before quality-gate.sh" >&2
  exit 1
fi

if ! grep -Fq 'permissions:' "$CI_WORKFLOW" || ! grep -Fq 'contents: read' "$CI_WORKFLOW"; then
  echo "ci.yml must use least-privilege read-only contents permissions" >&2
  exit 1
fi

if ! grep -Fq 'concurrency:' "$CI_WORKFLOW" || ! grep -Fq 'cancel-in-progress: true' "$CI_WORKFLOW"; then
  echo "ci.yml must cancel superseded runs" >&2
  exit 1
fi

if [[ ! -f "$RELEASE_WORKFLOW" ]]; then
  echo "release.yml must exist for tag publishing" >&2
  exit 1
fi

if ! grep -Fq 'GITHUB_REF_NAME' "$RELEASE_WORKFLOW" || ! grep -Fq 'version.env' "$RELEASE_WORKFLOW"; then
  echo "release.yml must verify that the pushed tag matches version.env" >&2
  exit 1
fi

if ! grep -Fq 'bash Scripts/tui-smoke-test.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run the TUI smoke/package checks" >&2
  exit 1
fi

if ! grep -Fq 'lint --strict --recursive Sources Tests Package.swift' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run Swift format checks in strict mode" >&2
  exit 1
fi

if ! grep -Fq 'command -v swift-format' "$QUALITY_GATE"; then
  echo "quality-gate.sh must use swift-format directly when available" >&2
  exit 1
fi

if ! grep -Fq '"$SWIFT_BIN" format --version' "$QUALITY_GATE"; then
  echo "quality-gate.sh must fall back to the Swift toolchain format subcommand" >&2
  exit 1
fi

if grep -Fq 'skipping Swift format checks' "$QUALITY_GATE"; then
  echo "quality-gate.sh must fail when Swift format checks are unavailable" >&2
  exit 1
fi

if grep -Fq 'name: Format' "$CI_WORKFLOW"; then
  echo "ci.yml must rely on quality-gate.sh for Swift format checks" >&2
  exit 1
fi

if grep -Fq 'name: Build' "$CI_WORKFLOW" || grep -Fq 'name: Test' "$CI_WORKFLOW"; then
  echo "ci.yml must rely on quality-gate.sh for Swift build and test checks" >&2
  exit 1
fi

if grep -Fq 'name: App package smoke' "$CI_WORKFLOW"; then
  echo "ci.yml must rely on quality-gate.sh for app package smoke checks" >&2
  exit 1
fi

if grep -Fq 'skipping tui smoke test on non-macOS' "$QUALITY_GATE"; then
  echo "quality-gate.sh must not skip Node/Ink TUI checks on non-macOS" >&2
  exit 1
fi

if ! grep -Fq 'UPDATEBAR_VERIFY_STATIC_ONLY=1 bash Scripts/verify-homebrew-metadata.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must verify Homebrew release metadata" >&2
  exit 1
fi

if ! grep -Fq 'bash Scripts/verify-homebrew-metadata-test.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run Homebrew metadata behavior checks" >&2
  exit 1
fi

if ! grep -Fq 'bash Scripts/install-local-smoke-test.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run local installer smoke checks" >&2
  exit 1
fi

if ! grep -Fq 'bash Scripts/install-release-smoke-test.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run release installer smoke checks" >&2
  exit 1
fi

if grep -Fq 'Scripts/quality-gate-contract-test.sh must not assign grep pipelines' "$ROOT/Scripts/script-syntax-test.sh"; then
  echo "script-syntax-test.sh must guard fragile grep pipeline assignments across Scripts/*.sh" >&2
  exit 1
fi

if ! grep -Fq '="?\$\(grep .*\|.*head' "$ROOT/Scripts/script-syntax-test.sh"; then
  echo "script-syntax-test.sh must catch quoted and unquoted grep/head command substitutions" >&2
  exit 1
fi

if ! grep -Fq '"$SWIFT_BIN" build --product updatebar' "$QUALITY_GATE"; then
  echo "quality-gate.sh must build the debug updatebar CLI before swift tests" >&2
  exit 1
fi

if ! grep -Fq 'export UPDATEBAR_TEST_BIN="$ROOT/.build/debug/updatebar"' "$QUALITY_GATE"; then
  echo "quality-gate.sh must point CLI tests at the freshly built updatebar binary" >&2
  exit 1
fi

if ! grep -Fq 'Swift XCTest not found' "$QUALITY_GATE"; then
  echo "quality-gate.sh must fail early with an actionable XCTest message" >&2
  exit 1
fi

if ! grep -Fq 'xcode-select -p' "$QUALITY_GATE"; then
  echo "quality-gate.sh must report the selected developer directory when XCTest is missing" >&2
  exit 1
fi

xctest_check_line="$(awk '/checking Swift XCTest availability/ { print NR; exit }' "$QUALITY_GATE")"
debug_build_line="$(awk '/building debug updatebar CLI for CLI tests/ { print NR; exit }' "$QUALITY_GATE")"
if [[ -z "$xctest_check_line" || -z "$debug_build_line" || "$xctest_check_line" -ge "$debug_build_line" ]]; then
  echo "quality-gate.sh must check Swift XCTest availability before the debug CLI build" >&2
  exit 1
fi

if ! grep -Fq 'export UPDATEBAR_BIN="$ROOT/.build/debug/updatebar"' "$QUALITY_GATE"; then
  echo "quality-gate.sh must point smoke scripts at the freshly built updatebar binary" >&2
  exit 1
fi

if ! grep -Fq 'bash Scripts/menubar-smoke-test.sh dist/UpdateBar.app' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run menu bar launch smoke checks" >&2
  exit 1
fi

if ! grep -Fq 'bash Scripts/app-archive-smoke-test.sh "$APP_ARCHIVE"' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run app archive smoke checks" >&2
  exit 1
fi
