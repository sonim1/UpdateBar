## 1. Swift Core Boundary Preparation

- [x] 1.1 Audit `UpdateBarCore` services used by `status`, `check`, `update`, `scan`, `init`, config, and approvals; list any CLI-only business logic that must move into core before TUI/Menu Bar work.
- [x] 1.2 Add or adjust `UpdateBarCore` APIs needed by both CLI and Menu Bar for operation planning, operation summaries, item-level results, and log metadata.
- [x] 1.3 Add Swift unit tests under `Tests/UpdateBarCoreTests` for any new core APIs and verify with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter UpdateBarCoreTests`.
- [x] 1.4 Confirm `UpdateBarCore` emits no CLI-specific human output and verify with targeted tests plus source review.

## 2. CLI Machine Interface

- [x] 2.1 Define JSONL event models for `started`, `item_started`, `log`, `item_finished`, `cancelled`, `failed`, and `finished` events in Swift.
- [x] 2.2 Add JSONL encoding helpers that write one valid JSON object per stdout line and keep human diagnostics on stderr.
- [x] 2.3 Add `--json-stream` support for `update` with item-level progress, logs, final status, and existing exit-code semantics.
- [x] 2.4 Add `--json-stream` support for `check` or document why `update` ships first and add a follow-up task if deferred.
- [x] 2.5 Add SIGINT/SIGTERM handling for long-running CLI operations so owned child commands are interrupted and cancellation is observable in JSONL mode.
- [x] 2.6 Add CLI contract tests under `Tests/UpdateBarCLITests` for stdout JSON isolation, JSONL event snapshots, exit codes, and cancellation behavior.
- [x] 2.7 Verify Swift CLI changes with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` and `UPDATEBAR_BIN=.build/debug/updatebar Scripts/e2e-edgecases.sh`.
- [x] 2.8 Add `check --json-stream` after `UpdateBarCore` has a check-specific event payload or callback contract.

## 3. Binary Resolution Contract

- [x] 3.1 Document binary resolution order: explicit `UPDATEBAR_BIN` or config, bundled binary, `PATH`, then development fallback.
- [x] 3.2 Implement or update Swift/Node binary resolver utilities so Ink TUI and Menu Bar subprocess fallback use the same resolution rules.
- [x] 3.3 Add tests for binary resolution override, bundled path, `PATH`, and development fallback behavior.
- [x] 3.4 Add packaging smoke checks for source build, release archive, Homebrew install layout, and macOS app bundle layout.

## 4. Ink TUI Package

- [x] 4.1 Create the Node/Ink package structure without changing `UpdateBarCore` or Swift CLI business rules.
- [x] 4.2 Add pinned Node dependencies for Ink, React, TypeScript, test runner, and lint/format tooling.
- [x] 4.3 Implement a subprocess adapter that runs `updatebar status --json`, parses JSON, and maps known exit codes to typed TUI states.
- [x] 4.4 Implement a JSONL stream reader that consumes CLI progress/log/result events without parsing human text.
- [x] 4.5 Implement TUI screens for main menu, status, selectable update list, operation progress, logs, config entry points, and exit.
- [x] 4.6 Implement keyboard navigation and cancellation that sends SIGINT to the active Swift CLI child process, then SIGTERM after a grace period.
- [x] 4.7 Add Node/Ink tests for rendering states, subprocess adapter parsing, JSONL stream parsing, missing binary errors, invalid JSON errors, and cancellation behavior.
- [x] 4.8 Verify TUI work with the selected package manager commands such as `npm test`, `npm run typecheck`, and `npm run lint` after the package manager is chosen.

## 5. macOS Menu Bar Architecture

- [x] 5.1 Define a Menu Bar service adapter that prefers direct `UpdateBarCore` calls for status, check, update, config, approvals, and logs.
- [x] 5.2 Keep or add a CLI subprocess fallback adapter that consumes only documented JSON/JSONL contracts and never parses human output.
- [x] 5.3 Add native Menu Bar actions for Check Now, Run Updates, Open TUI, Open Config, View Logs, and Quit.
- [x] 5.4 Implement non-blocking in-progress, success, failure, and cancellation UI states for Menu Bar actions.
- [x] 5.5 Implement Open TUI by launching a terminal with the configured TUI command and required environment such as `UPDATEBAR_BIN` and `UPDATEBAR_HOME`.
- [x] 5.6 Add Menu Bar tests under `Tests/UpdateBarMenuBarTests` for status formatting, action availability, direct-core adapter behavior, CLI fallback behavior, and Open TUI command construction.
- [x] 5.7 Verify Menu Bar work with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter UpdateBarMenuBarTests`.

## 6. Documentation

- [x] 6.1 Update `docs/cli.md` with JSONL streaming contracts, exit-code behavior, stdout/stderr rules, and cancellation behavior.
- [x] 6.2 Add architecture documentation explaining `UpdateBarCore`, Swift CLI, Ink TUI, and macOS Menu Bar responsibility boundaries.
- [x] 6.3 Update README usage sections for CLI automation, Ink TUI launch, and Menu Bar launch after those entrypoints exist.
- [x] 6.4 Add troubleshooting docs for binary path resolution, missing TUI install, invalid JSON/JSONL contract errors, and Menu Bar Open TUI failures.

## 7. Packaging and Release Checks

- [x] 7.1 Update release scripts so the Swift CLI remains installable without Node or Ink dependencies.
- [x] 7.2 Add packaging support for the Ink TUI entrypoint after the Node package name and command name are selected.
- [x] 7.3 Update macOS app bundling to include or locate the Swift CLI binary and, if shipped, the TUI entrypoint.
- [x] 7.4 Update Homebrew formula or tap strategy to document whether it installs CLI only, CLI plus TUI, or separate formulae.
- [x] 7.5 Verify package behavior with `Scripts/build-release.sh`, `Scripts/archive-smoke-test.sh`, `Scripts/package-app.sh`, and any Node package smoke command added for the TUI.

## 8. Final Verification

- [x] 8.1 Run full Swift verification with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- [x] 8.2 Run CLI edge-case verification with `UPDATEBAR_BIN=.build/debug/updatebar Scripts/e2e-edgecases.sh`.
- [x] 8.3 Run all Node/Ink verification commands defined by the TUI package.
- [x] 8.4 Run packaging smoke checks for release archive, Homebrew path assumptions, and macOS app bundle behavior.
- [x] 8.5 Review the diff to confirm no business logic was duplicated in Ink or Menu Bar presentation code.
