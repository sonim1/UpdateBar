# TUI runtime and packaged app E2E implementation plan

> **For agentic workers:** Execute inline with `superpowers:executing-plans`; use `omo:review-work` for the final review.

**Goal:** Make the TUI's Node support truthful and continuously test the packaged macOS app's complete first-use update journey.

**Architecture:** Keep the existing CLI, core, trust rules, and app behavior intact. Align Node metadata with the locked dependencies and verify clean installs on a runtime matrix. Use Apple's XCUITest against `dist/UpdateBar.app`, with temporary homes and a synthetic Homebrew executable; every action under test goes through the app's existing UI.

**Tech Stack:** Swift/XCTest/XCUITest, SwiftPM, Xcode, Bash/Ruby contract tests, npm, GitHub Actions.

## Scope and assumptions

- The user approved recommendation 1 (Node support/CI) and 2 (packaged app E2E). VoiceOver and the separate minimum-window work are excluded.
- Ink requires Node 22; ESLint requires 22.13 or a version at least 24. Use `^22.13.0 || >=24.0.0`, with CI covering the minimum and current 22/24/26 lines.
- No new dependencies, production test hooks, automatic approvals, live tool upgrades, installed-app changes, or user configuration changes.
- E2E starts with an empty registry, scans and registers a fixture, reviews exact commands, checks, updates, reads history, and relaunches. Also cover registration without approval and a failed/no-op update.
- Store screenshots and test results as CI artifacts. Preserve local evidence outside Git.

## Task 1: Node runtime support

**Files:** `tui/package.json`, `tui/package-lock.json`, `Scripts/tui-smoke-test.sh`, `.github/workflows/ci.yml`, `Scripts/ci-workflow-test.sh`, `Scripts/quality-gate-contract-test.sh`, `README.md`, `tui/README.md`, `docs/development.md`.

- [ ] Reproduce the mismatch with a strict clean install on Node 20; retain the `EBADENGINE` output.
- [ ] Extend the workflow contract to require the supported Node matrix, exact event SHA, read-only permissions, and failure propagation; run it and observe failure against the old workflow.
- [ ] Set the package and lockfile root engines to `^22.13.0 || >=24.0.0`; use Node 24 for the macOS quality gate.
- [ ] Add an isolated Linux TUI matrix for `22.13.0`, `22.x`, `24.x`, and `26.x`; run the existing smoke script with `npm ci --engine-strict`.
- [ ] Document the supported runtime and source setup. Run the contract and each runtime's clean install, typecheck, tests, lint, build, package check, and real PTY navigation.

Verification commands:

```bash
rtk proxy bash Scripts/ci-workflow-test.sh
rtk proxy bash Scripts/quality-gate-contract-test.sh
rtk proxy bash Scripts/tui-smoke-test.sh
rtk proxy bash Scripts/tui-input-test.sh
```

Expected: workflow negative mutations rejected; all supported versions install without engine warnings, and the built TUI accepts navigation and exits normally.

## Task 2: Packaged macOS app E2E

**Files:** `Tests/PackagedAppE2E/` (test-only Xcode project, shared scheme and UI tests), `Scripts/app-e2e.sh`, `Scripts/app-e2e-test.sh`, `.github/workflows/app-e2e.yml`, workflow contract coverage, `Scripts/quality-gate.sh`, `docs/development.md`.

- [ ] Add runner contract probes before the runner: missing bundle must fail, paths containing spaces must remain intact, failed Xcode tests must propagate, and test output must be retained.
- [ ] Create a test-only macOS UI test target. Launch the bundle using `XCUIApplication(url:)`; do not import the production controllers or substitute their services.
- [ ] Create each fixture under a new temporary directory. Set only the child app's `HOME`, `CFFIXED_USER_HOME`, `UPDATEBAR_HOME`, and `PATH`. Use the bundled CLI for read-only verification of registry, approvals, status, and history.
- [ ] Drive the first-use journey through the existing status item, dashboard sidebar, scan checkbox, exact-command review controls, check/update buttons, and Logs view. Assert that registration alone runs no update and that both successful and unsuccessful updates reflect actual installed versions.
- [ ] Terminate and relaunch the same bundle with the same isolated profile; assert persisted registry, approvals, installed version, and history. Tear down only test-owned processes and directories.
- [ ] Add a read-only, exact-event-SHA GitHub Actions workflow that packages the app, runs XCUITest, and uploads `.xcresult` evidence on success or failure.
- [ ] Run the runner/workflow contracts, the full quality gate, actual packaged E2E, and hands-on QA. Record exact build SHA and artifact paths.

Verification commands:

```bash
rtk proxy bash Scripts/app-e2e-test.sh
rtk proxy bash Scripts/quality-gate.sh
rtk proxy bash Scripts/app-e2e.sh dist/UpdateBar.app
```

Expected: tests operate only on synthetic tools; unapproved commands never update, successful updates change the fixture version, unsuccessful updates are not recorded as success, and state survives relaunch.

## Task 3: Delivery and cleanup

- [ ] Commit each independent change with its test evidence; review the exact final diff from a dedicated locked worktree.
- [ ] Run root-owned happy-path, risky-edge, and adjacent-regression QA; one strict read-only gate reviewer must approve.
- [ ] Push, open the PR, verify every exact-head check, fix failures, and integrate through the authorized repository workflow.
- [ ] Verify any resulting release/deployment, document the outcome and limits, and remove only task-owned worktrees, branches, incomplete installs, and temporary build artifacts.

## Environment note

Initial Node smoke and workflow baseline attempts encountered `ENOSPC`. The workflow baseline passed after removing only the repository's regenerable Swift index cache. Local installs/builds require additional disk space; do not misreport an environment failure as an application regression or a successful verification.
