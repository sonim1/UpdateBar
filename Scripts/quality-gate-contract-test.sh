#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUALITY_GATE="$ROOT/Scripts/quality-gate.sh"
APP_DMG_SMOKE="$ROOT/Scripts/app-dmg-smoke-test.sh"
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

CHECKSUM_TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$CHECKSUM_TEST_TMP"' EXIT
CHECKSUM_RUN_BLOCK="$(ruby -rpsych -e '
  workflow = Psych.safe_load(File.read(ARGV.fetch(0)), aliases: true)
  steps = workflow.fetch("jobs").fetch("publish").fetch("steps")
  matches = steps.select do |step|
    step.is_a?(Hash) && step["name"] == "Verify downloaded checksums"
  end
  abort "expected exactly one Verify downloaded checksums step" unless matches.length == 1
  run = matches.first["run"]
  abort "checksum verification step must have a run block" unless run.is_a?(String)
  print run
' "$RELEASE_WORKFLOW")"
CHECKSUM_TEST_ROOT="$CHECKSUM_TEST_TMP/repo-root"
CHECKSUM_TEST_DIST="$CHECKSUM_TEST_ROOT/dist"
CHECKSUM_TEST_ASSET="UpdateBar-contract.tar.gz"
mkdir -p "$CHECKSUM_TEST_DIST"
printf 'release artifact\n' >"$CHECKSUM_TEST_DIST/$CHECKSUM_TEST_ASSET"
if command -v shasum >/dev/null 2>&1; then
  CHECKSUM_TEST_SHA="$(shasum -a 256 "$CHECKSUM_TEST_DIST/$CHECKSUM_TEST_ASSET" | awk '{print $1}')"
else
  CHECKSUM_TEST_SHA="$(sha256sum "$CHECKSUM_TEST_DIST/$CHECKSUM_TEST_ASSET" | awk '{print $1}')"
fi
printf '%s  %s\n' "$CHECKSUM_TEST_SHA" "$CHECKSUM_TEST_ASSET" \
  >"$CHECKSUM_TEST_DIST/$CHECKSUM_TEST_ASSET.sha256"
if ! (
  cd "$CHECKSUM_TEST_ROOT"
  bash -e -o pipefail -c "$CHECKSUM_RUN_BLOCK"
); then
  echo "release checksum step must verify basename entries from a repo-root/dist layout" >&2
  exit 1
fi
printf 'tampered\n' >>"$CHECKSUM_TEST_DIST/$CHECKSUM_TEST_ASSET"
set +e
(
  cd "$CHECKSUM_TEST_ROOT"
  bash -e -o pipefail -c "$CHECKSUM_RUN_BLOCK"
) >/dev/null 2>&1
CHECKSUM_TAMPER_STATUS=$?
set -e
if [[ "$CHECKSUM_TAMPER_STATUS" -eq 0 ]]; then
  echo "release checksum step must reject tampered artifact bytes" >&2
  exit 1
fi

if ! grep -Fq 'GITHUB_REF_NAME' "$RELEASE_WORKFLOW" || ! grep -Fq 'version.env' "$RELEASE_WORKFLOW"; then
  echo "release.yml must verify that the pushed tag matches version.env" >&2
  exit 1
fi

if ! grep -Fq 'workflow_dispatch:' "$RELEASE_WORKFLOW"; then
  echo "release.yml must support manual dry-run dispatches" >&2
  exit 1
fi

if ! grep -Fq 'swift test' "$RELEASE_WORKFLOW"; then
  echo "release.yml must run Swift tests before publishing release assets" >&2
  exit 1
fi

if ! grep -Fq 'Scripts/extract-changelog-section.sh "$GITHUB_REF_NAME"' "$RELEASE_WORKFLOW" \
  || ! grep -Fq 'body_path: release-notes.md' "$RELEASE_WORKFLOW"; then
  echo "release.yml must publish release notes from CHANGELOG.md" >&2
  exit 1
fi

if ! grep -Fq 'fail_on_unmatched_files: true' "$RELEASE_WORKFLOW"; then
  echo "release.yml must fail when release artifact globs do not match" >&2
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

if ! grep -Fq 'shellcheck --severity=warning Scripts/*.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must fail on ShellCheck warnings and errors" >&2
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

if ! grep -Fq '="?\$\(.*\|.*(head|tail)' "$ROOT/Scripts/script-syntax-test.sh"; then
  echo "script-syntax-test.sh must catch assigned command substitutions piped to head or tail" >&2
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

if ! grep -Fq 'bash Scripts/build-app-dmg-test.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run the app DMG builder contract without live notarization" >&2
  exit 1
fi

if grep -Eq 'build-app-archive|app-archive-smoke|archive-version-smoke' \
  "$QUALITY_GATE" "$RELEASE_WORKFLOW" "$APP_DMG_SMOKE"; then
  echo "live quality and release callers must not reference obsolete app archive scripts" >&2
  exit 1
fi

if grep -Fq 'bash Scripts/build-app-dmg.sh' "$QUALITY_GATE"; then
  echo "the normal quality gate must not perform live signing or notarization" >&2
  exit 1
fi

if ! grep -Fq 'APP_DMG="$(bash Scripts/build-app-dmg.sh)"' "$RELEASE_WORKFLOW" \
  || ! grep -Fq 'bash Scripts/app-dmg-smoke-test.sh "$APP_DMG"' "$RELEASE_WORKFLOW" \
  || ! grep -Fq 'dist/*.dmg' "$RELEASE_WORKFLOW"; then
  echo "release.yml must build, smoke-check, and upload the canonical app DMG" >&2
  exit 1
fi

if ! grep -Fq 'SPARKLE_PUBLIC_ED_KEY: ${{ vars.SPARKLE_PUBLIC_ED_KEY }}' "$RELEASE_WORKFLOW" \
  || ! grep -Fq 'DEVELOPER_ID_APPLICATION=$IDENTITY' "$RELEASE_WORKFLOW" \
  || ! grep -Fq 'NOTARYTOOL_KEYCHAIN_PROFILE=updatebar-notary' "$RELEASE_WORKFLOW"; then
  echo "release.yml must provide the standard signing, notary, and Sparkle inputs" >&2
  exit 1
fi

if ! grep -Fq '$(/usr/bin/uname -m)' "$RELEASE_WORKFLOW" \
  || ! grep -Fq 'arm64 macOS runner' "$RELEASE_WORKFLOW"; then
  echo "release.yml must fail closed unless the macOS app runner is arm64" >&2
  exit 1
fi

if grep -Fq 'building unsigned app' "$RELEASE_WORKFLOW" \
  || grep -Fq 'app will be signed but not notarized' "$RELEASE_WORKFLOW"; then
  echo "release.yml must fail closed rather than publish unsigned or unnotarized apps" >&2
  exit 1
fi
