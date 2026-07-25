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

ruby -e '
  quality_gate = File.binread(ARGV.fetch(0))
  expected_contracts = %w[
    Scripts/release-tooling-test.sh
    Scripts/setup-update-hosting-test.sh
    Scripts/generate-appcast-test.sh
    Scripts/publish-update-test.sh
    Scripts/generate-release-manifest-test.sh
    Scripts/publish-release-test.sh
    Scripts/dispatch-homebrew-update-test.sh
    Scripts/release-workflow-test.sh
  ]
  invocations = quality_gate.lines.map do |line|
    match = line.match(/\A\s*bash\s+(Scripts\/[A-Za-z0-9-]+-test[.]sh)\s*\z/)
    match && match[1]
  end.compact
  counts = invocations.each_with_object(Hash.new(0)) { |path, result| result[path] += 1 }
  missing = expected_contracts.reject { |path| counts[path] == 1 }
  duplicated = expected_contracts.select { |path| counts[path].to_i > 1 }
  unless missing.empty? && duplicated.empty?
    warn "quality-gate.sh release contract coverage is incomplete or duplicated"
    exit 1
  end

  expected_syntax = %w[
    Scripts/setup-update-hosting.sh
    Scripts/generate-appcast.sh
    Scripts/publish-update.sh
    Scripts/generate-release-manifest.sh
    Scripts/publish-release.sh
    Scripts/dispatch-homebrew-update.sh
    Scripts/build-release.sh
    Scripts/package-app.sh
    Scripts/build-app-icon.sh
    Scripts/build-app-dmg.sh
    Scripts/app-dmg-smoke-test.sh
  ].sort
  array_match = quality_gate.match(/\nRELEASE_SYNTAX_SCRIPTS=\(\n(?<body>.*?)\n\)\n/m)
  abort "quality-gate.sh must declare release syntax coverage" unless array_match
  syntax_paths = array_match[:body].lines.map do |line|
    match = line.match(/\A\s*"(Scripts\/[A-Za-z0-9.-]+[.]sh)"\s*\z/)
    abort "release syntax coverage must contain literal script paths" unless match
    match[1]
  end.compact
  unless syntax_paths.length == syntax_paths.uniq.length && syntax_paths.sort == expected_syntax
    warn "quality-gate.sh release syntax coverage does not match the supported release scripts"
    exit 1
  end
  syntax_runs = quality_gate.scan(/^bash -n "\$\{RELEASE_SYNTAX_SCRIPTS\[@\]\}"$/).length
  abort "quality-gate.sh must syntax-check the declared release scripts exactly once" unless syntax_runs == 1
' "$QUALITY_GATE"

for obsolete_script in \
  Scripts/build-app-archive.sh \
  Scripts/build-app-archive-test.sh \
  Scripts/app-archive-smoke-test.sh \
  Scripts/archive-version-smoke-test.sh; do
  if [[ -e "$ROOT/$obsolete_script" || -L "$ROOT/$obsolete_script" ]]; then
    echo "obsolete app archive script must be absent: $obsolete_script" >&2
    exit 1
  fi
done

CHECKSUM_TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$CHECKSUM_TEST_TMP"' EXIT
CHECKSUM_TOOL_PATHS=()
REAL_SHASUM="$(command -v shasum || true)"
REAL_SHA256SUM="$(command -v sha256sum || true)"
if [[ -n "$REAL_SHASUM" ]]; then
  mkdir "$CHECKSUM_TEST_TMP/shasum-bin"
  ln -s "$REAL_SHASUM" "$CHECKSUM_TEST_TMP/shasum-bin/shasum"
  CHECKSUM_TOOL_PATHS+=("$CHECKSUM_TEST_TMP/shasum-bin")
fi
if [[ -n "$REAL_SHA256SUM" ]]; then
  mkdir "$CHECKSUM_TEST_TMP/sha256sum-bin"
  ln -s "$REAL_SHA256SUM" "$CHECKSUM_TEST_TMP/sha256sum-bin/sha256sum"
  CHECKSUM_TOOL_PATHS+=("$CHECKSUM_TEST_TMP/sha256sum-bin")
fi
if [[ "${#CHECKSUM_TOOL_PATHS[@]}" -eq 0 ]]; then
  echo "shasum or sha256sum is required for release checksum contract tests" >&2
  exit 1
fi
extract_checksum_run_block() {
  ruby -rpsych -e '
    workflow = Psych.safe_load(File.read(ARGV.fetch(0)), aliases: true)
    name = ARGV.fetch(1)
    steps = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
    matches = steps.select do |step|
      step.is_a?(Hash) && step["name"] == name
    end
    abort "expected exactly one #{name} step" unless matches.length == 1
    run = matches.first["run"]
    abort "#{name} step must have a run block" unless run.is_a?(String)
    print run
  ' "$RELEASE_WORKFLOW" "$1"
}
BUILD_CHECKSUM_RUN_BLOCK="$(extract_checksum_run_block "Verify checksums")"
PUBLISH_CHECKSUM_RUN_BLOCK="$(extract_checksum_run_block "Verify downloaded checksums")"

if ! bash "$ROOT/Scripts/build-release-archive-test.sh" >/dev/null 2>&1; then
  echo "release archive fixture must produce a portable CLI checksum" >&2
  exit 1
fi
CLI_ARCHIVES=("$ROOT"/dist/updatebar-*.tar.gz)
if [[ "${#CLI_ARCHIVES[@]}" -ne 1 || ! -f "${CLI_ARCHIVES[0]}" ]]; then
  echo "release archive fixture must produce exactly one CLI archive" >&2
  exit 1
fi
CLI_ARCHIVE_SOURCE="${CLI_ARCHIVES[0]}"
CLI_CHECKSUM_SOURCE="$CLI_ARCHIVE_SOURCE.sha256"
if [[ ! -f "$CLI_CHECKSUM_SOURCE" ]]; then
  echo "release archive fixture did not produce its CLI checksum" >&2
  exit 1
fi

CHECKSUM_TEST_ROOT="$CHECKSUM_TEST_TMP/repo-root"
CHECKSUM_TEST_DIST="$CHECKSUM_TEST_ROOT/dist"
CLI_TEST_ASSET="$(basename "$CLI_ARCHIVE_SOURCE")"
DMG_TEST_ASSET="UpdateBar-contract.dmg"
mkdir -p "$CHECKSUM_TEST_DIST"
cp "$CLI_ARCHIVE_SOURCE" "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET"
cp "$CLI_CHECKSUM_SOURCE" "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET.sha256"
printf 'app DMG artifact\n' >"$CHECKSUM_TEST_DIST/$DMG_TEST_ASSET"
if command -v shasum >/dev/null 2>&1; then
  DMG_TEST_SHA="$(shasum -a 256 "$CHECKSUM_TEST_DIST/$DMG_TEST_ASSET" | awk '{print $1}')"
else
  DMG_TEST_SHA="$(sha256sum "$CHECKSUM_TEST_DIST/$DMG_TEST_ASSET" | awk '{print $1}')"
fi
printf '%s  %s\n' "$DMG_TEST_SHA" "$DMG_TEST_ASSET" \
  >"$CHECKSUM_TEST_DIST/$DMG_TEST_ASSET.sha256"

run_checksum_block() {
  local run_block="$1"
  local checksum_path="$2"
  (
    cd "$CHECKSUM_TEST_ROOT"
    PATH="$checksum_path" /bin/bash -e -o pipefail -c "$run_block"
  )
}

expect_checksum_failure() {
  local run_block="$1"
  local checksum_path="$2"
  local scenario="$3"
  local status=0
  set +e
  run_checksum_block "$run_block" "$checksum_path" >/dev/null 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "release checksum step accepted $scenario" >&2
    exit 1
  fi
}

for checksum_step in build publish; do
  if [[ "$checksum_step" == "build" ]]; then
    checksum_run_block="$BUILD_CHECKSUM_RUN_BLOCK"
  else
    checksum_run_block="$PUBLISH_CHECKSUM_RUN_BLOCK"
  fi
  for checksum_tool_path in "${CHECKSUM_TOOL_PATHS[@]}"; do
    if ! run_checksum_block "$checksum_run_block" "$checksum_tool_path" >/dev/null; then
      echo "$checksum_step checksum step must verify CLI and DMG basename entries from dist" >&2
      exit 1
    fi

    printf 'tampered CLI\n' >>"$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET"
    expect_checksum_failure "$checksum_run_block" "$checksum_tool_path" "tampered CLI bytes"
    cp "$CLI_ARCHIVE_SOURCE" "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET"

    printf 'tampered DMG\n' >>"$CHECKSUM_TEST_DIST/$DMG_TEST_ASSET"
    expect_checksum_failure "$checksum_run_block" "$checksum_tool_path" "tampered DMG bytes"
    printf 'app DMG artifact\n' >"$CHECKSUM_TEST_DIST/$DMG_TEST_ASSET"

    : >"$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET.sha256"
    expect_checksum_failure "$checksum_run_block" "$checksum_tool_path" "an empty checksum file"
    cp "$CLI_CHECKSUM_SOURCE" "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET.sha256"

    rm -f "$CHECKSUM_TEST_DIST"/*.sha256
    expect_checksum_failure "$checksum_run_block" "$checksum_tool_path" "missing checksum files"
    cp "$CLI_CHECKSUM_SOURCE" "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET.sha256"
    printf '%s  %s\n' "$DMG_TEST_SHA" "$DMG_TEST_ASSET" \
      >"$CHECKSUM_TEST_DIST/$DMG_TEST_ASSET.sha256"

    rm -f "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET"
    expect_checksum_failure "$checksum_run_block" "$checksum_tool_path" "a missing release artifact"
    cp "$CLI_ARCHIVE_SOURCE" "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET"

    rm -f "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET.sha256"
    ln -s "$CLI_CHECKSUM_SOURCE" "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET.sha256"
    expect_checksum_failure "$checksum_run_block" "$checksum_tool_path" "a symlink checksum file"
    rm -f "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET.sha256"
    cp "$CLI_CHECKSUM_SOURCE" "$CHECKSUM_TEST_DIST/$CLI_TEST_ASSET.sha256"
  done
done

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
