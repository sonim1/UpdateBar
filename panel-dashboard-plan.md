# Manage Panel + Dashboard Plan (v0.4.0)

Add a GUI management panel and dashboard to the menu bar app. The two feature requirements are:

1. **Scan/item management panel** — Instead of scanning directly from the menu, open a panel that lists registered items (the manifest) and scan candidates by category and supports enabling, disabling, and registering items.
2. **Dashboard** — Summarize update history and the number of pending updates with charts and tiles. Detailed information remains available in the list described above.

## Current State (Already Available)

- `manifest.json` items have `enabled: Bool` and `category: String` fields (docs/manifest.md).
- The CLI implements `updatebar enable <id>` and `disable <id>` (docs/cli.md).
- `updatebar scan --json` returns candidates with category, confidence, and capability information.
- The menu bar app uses a direct core adapter with a CLI subprocess fallback through `MenuBarServicing`. View models live in the pure `UpdateBarMenuBar` target, while the shell lives in `UpdateBarMenuBarApp`.

## Missing Pieces (To Be Built)

- **Update history store** — `state.json` records only `last_checked`. Without time-series data showing when updates happened, charts cannot be produced.
- A GUI window. The current app has only an `NSMenu`.

## Architecture Decisions

- Host a **SwiftUI window** from the AppKit delegate using `NSHostingView`. Because the deployment target is macOS 13+ (`LSMinimumSystemVersion`), use **Swift Charts** with no external dependencies.
- Showing a window from an accessory app (`LSUIElement`) requires handling `NSApp.activate`.
- Keep view models and state types as pure types in the `UpdateBarMenuBar` target and unit-test them. Keep SwiftUI views thin.
- Unify data access by extending the `MenuBarServicing` protocol and implement both core and CLI adapters.
- The CLI remains the source of truth, consistent with the open-source/agent philosophy: expose history first through `updatebar history --json`, with the GUI acting as a consumer.

## M1 — Panel Shell + Registered Item Management

- Add `Manage Items...` to the menu. Fold the existing `Scan & Add` menu item into the panel.
- Window structure: sidebar/tabs = Overview | Items | Scan. M1 implements only Items.
- Items tab: a list grouped by category. Each row shows the name, current/latest version, status badge (`outdated`/`ok`/`untrusted`/`error`), and an enable/disable toggle.
- Extend `MenuBarServicing` with `listItems()` (a manifest/status join) and `setEnabled(id:enabled:)`. The core adapter calls `RegistryService` directly; the CLI adapter invokes the `enable`/`disable` subcommands.
- Refresh status and update the menu badge after a toggle.
- Tests: view-model unit tests for grouping, sorting, and toggle state transitions, plus adapter contract tests.

## M2 — Scan Tab

- Run scans only inside the panel, initiated by a button; do not run them immediately from the menu.
- Candidate list: group by category, show confidence/capability, and distinguish already registered items.
- Checkbox selection → registration. Reuse the existing scan-init selection/registration logic.
- Preserve the existing security boundary for new registrations: trust is unapproved by default (`trust.approved_commands` is empty), and approval uses the existing approvals flow.
- Tests: candidate view-model mapping and an end-to-end test that registration updates the manifest.

## M3 — History Store

- Add `~/.updatebar/history.jsonl`. Event schema (v1):
  `{"schema_version":1,"event":"update_finished","id":...,"from":...,
  "to":...,"outcome":"updated|failed","at":ISO8601}` plus a `check_finished` summary event containing the outdated count.
- Recording points: the core `UpdateRunner` completion hook and the check summary point.
- Rotation: truncate the beginning when the file exceeds a size cap (for example, 512 KB), following the existing log-rotation pattern.
- Add `updatebar history [--json] [--since <date>]` to the CLI.
- Tests: HistoryStore append/rotation/parsing, the CLI output contract, and an end-to-end test confirming that an update records an event.

## M4 — Overview Tab (Dashboard)

- Statistic tiles: pending update count, pending approval count, and last check/update times.
- Swift Charts bar chart: daily (or weekly) update counts for the last four weeks, aggregated from `history.jsonl`.
- Clicking a tile opens the Items tab with the corresponding filter.
- Tests: unit-test aggregation/bucketing logic. Keep the chart view thin and do not add snapshot tests.

## M5 — Polish / Release

- Add the panel-opening path to the menu bar smoke test.
- Update docs/menu-bar.md, docs/cli.md (history), and CHANGELOG.
- Release v0.4.0. Adding history to the CLI requires a minor version bump. Update tap SHAs after the release using the existing process.

## Risks / Notes

- Handle accessory-app window activation and focus with `NSApp.activate(ignoringOtherApps:)`.
- Include `schema_version` in the history schema from v1 to leave room for migration.
- The overlap between panel and TUI functionality is intentional: the TUI serves terminal users, while the panel serves GUI users.
- Scanning/registration must never auto-approve commands in the panel; the security boundary remains unchanged.
