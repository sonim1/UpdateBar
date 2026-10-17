# TUI runtime and packaged app E2E implementation plan

> **For agentic workers:** Execute inline with `superpowers:executing-plans`; use `omo:review-work` for the final review.

**Goal:** Make the TUI's Node support truthful and continuously test the packaged macOS app's complete first-use update journey.

**Architecture:** Preserve existing CLI contracts and trust rules. Align Node metadata with the locked dependencies and verify clean installs on a runtime matrix. Use Apple's XCUITest against `dist/UpdateBar.app`, with temporary homes and synthetic tool executables; every action under test goes through the app's existing UI. Fix a production defect only when this work reproduces it with regression coverage.

**Tech Stack:** Swift/XCTest/XCUITest, SwiftPM, Xcode, Bash/Ruby contract tests, npm, GitHub Actions.

## Scope and assumptions

- The user approved recommendation 1 (Node support/CI) and 2 (packaged app E2E). VoiceOver and the separate minimum-window work are excluded.
- Ink requires Node 22; ESLint requires 22.13 or a version at least 24. Use `^22.13.0 || >=24.0.0`, with CI covering the minimum and current 22/24/26 lines.
- No new dependencies, production test hooks, automatic approvals, live tool upgrades, installed-app changes, or user configuration changes.
- E2E starts with an empty registry, scans and registers a fixture, reviews exact commands, checks, updates, reads history, and relaunches. Also cover scans without registration, registration without approval, and a failed/no-op update.
- Store screenshots and test results as CI artifacts. Preserve local evidence outside Git.

## Task 1: Node runtime support

**Files:** `tui/package.json`, `tui/package-lock.json`, `Scripts/tui-smoke-test.sh`, `.github/workflows/ci.yml`, `Scripts/ci-workflow-test.sh`, `Scripts/quality-gate-contract-test.sh`, `README.md`, `tui/README.md`, `docs/development.md`.

- [x] Reproduce the package/workflow mismatch with contract checks against the locked dependency engines. Local clean-install attempts hit `ENOSPC`; the planned Node 20 installation was replaced by metadata regression coverage and strict installs on the supported CI matrix.
- [x] Extend the workflow contract to require the supported Node matrix, exact event SHA, read-only permissions, and failure propagation; run it and observe failure against the old workflow.
- [x] Set the package and lockfile root engines to `^22.13.0 || >=24.0.0`; use Node 24 for the macOS quality gate.
- [x] Add an isolated Linux TUI matrix for `22.13.0`, `22.x`, `24.x`, and `26.x`; run the existing smoke script with `npm ci --engine-strict`.
- [x] Document the supported runtime and source setup. All four CI lanes passed clean install, typecheck, 152 tests, lint, build, and package checks. Run real PTY navigation on local Node 22.22.2, 24.19.0, and 26.5.1 against unchanged TUI sources; retain transcripts.

Verification commands:

```bash
rtk proxy bash Scripts/ci-workflow-test.sh
rtk proxy bash Scripts/quality-gate-contract-test.sh
rtk proxy bash Scripts/tui-smoke-test.sh
rtk proxy bash Scripts/tui-input-test.sh
```

Expected: workflow negative mutations rejected; all supported versions install without engine warnings, and the built TUI accepts navigation and exits normally.

## Task 2: Packaged macOS app E2E

**Files:** `Tests/PackagedAppE2E/` (test-only Xcode project, shared scheme and UI tests), `Scripts/app-e2e.sh`, `Scripts/app-e2e-test.sh`, `.github/workflows/ci.yml`, workflow contract coverage, `Scripts/quality-gate.sh`, `docs/development.md`, `Sources/UpdateBarCore/Scan/ScanService.swift`, `Tests/UpdateBarCoreTests/BrewScanVersionTests.swift`.

- [x] Add runner contract probes before the runner: missing bundle must fail, paths containing spaces must remain intact, failed Xcode tests must propagate, and test output must be retained.
- [x] Create a test-only macOS UI test target. Launch the bundle using `XCUIApplication(url:)`; do not import the production controllers or substitute their services.
- [x] Create each fixture under a new temporary directory. Set only the child app's `HOME`, `CFFIXED_USER_HOME`, `UPDATEBAR_HOME`, and `PATH`. Use the bundled CLI for read-only verification of registry, approvals, status, and history.
- [x] Drive the first-use journey through the existing status item, dashboard sidebar, scan checkbox, exact-command review controls, check/update buttons, and Logs view. Assert that registration alone runs no update and that both successful and unsuccessful updates reflect actual installed versions.
- [x] Terminate and relaunch the same bundle with the same isolated profile; assert persisted registry, approvals, installed version, and history. Tear down only test-owned processes and directories.
- [x] Add packaged UI tests to the required read-only, exact-event-SHA macOS CI job after packaging. Upload `.xcresult` evidence on success or failure. CI failure must block automatic releases; remove the exploratory standalone workflow.
- [x] Reproduce digit-containing Homebrew names being parsed as installed versions (`node@22` -> `22`, `python@3.13` -> `3.13`, `e2e-fixture` -> `2e-fixture`). Add two regression tests and constrain the generated parser to the version after the formula name.
- [ ] Run the runner/workflow contracts, the full quality gate, actual packaged E2E, and hands-on QA. Record exact build SHA and artifact paths.

Verification commands:

```bash
rtk proxy bash Scripts/app-e2e-test.sh
rtk proxy bash Scripts/quality-gate.sh
rtk proxy bash Scripts/app-e2e.sh dist/UpdateBar.app
```

Expected: tests operate only on synthetic tools; repeated scans never register tools, unapproved commands never update, successful updates change the fixture version, unsuccessful updates are not recorded as success, and state survives relaunch.

The production menu bar service deliberately adds standard tool directories to
PATH. The packaged suite therefore shadows every version probe and npm/Brew
operation with fixture executables. A completely empty detector result remains
covered by controller/model tests; the packaged suite covers repeated real
scans without introducing a production test bypass for PATH discovery.

## Task 3: Delivery and cleanup

- [ ] Commit each independent change with its test evidence; review the exact final diff from a dedicated locked worktree.
- [ ] Run root-owned happy-path, risky-edge, and adjacent-regression QA; one strict read-only gate reviewer must approve.
- [ ] Push, open the PR, verify every exact-head check, fix failures, and integrate through the authorized repository workflow.
- [ ] Verify any resulting release/deployment, document the outcome and limits, and remove only task-owned worktrees, branches, incomplete installs, and temporary build artifacts.

## Environment note

Initial Node smoke and workflow baseline attempts encountered `ENOSPC`. The workflow baseline passed after removing only the repository's regenerable Swift index cache. Local installs/builds require additional disk space; do not misreport an environment failure as an application regression or a successful verification.

The local full gate also hit `ENOSPC` during compilation. Task-created Clang
modules and incomplete task builds/installs were removed; the root compiled
cache and user app were preserved. Final verification uses fresh remote builds.
Implementation details and evidence limits are documented in
`docs/runtime-packaged-e2e-2026-10-17.md`; delivery evidence is kept in the local
task ledger and the exact-head PR checks.
