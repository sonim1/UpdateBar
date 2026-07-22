# Dashboard Sidebar And Scan Toggle Design

## Goal

Unify `Overview`, `Items`, and `Scan & Add` in one Dashboard window with a
native left sidebar. Reduce persistent explanatory text across all three
sections, and make each scan-result checkbox directly control whether UpdateBar
tracks that tool.

This design supersedes the top segmented-tab navigation in
`2026-07-14-unified-dashboard-window-design.md` and the standalone Scan panel
described in `docs/menu-bar.md`.

## Success Criteria

- The Dashboard uses one reusable window with a left sidebar containing
  `Overview`, `Items`, and `Scan & Add`.
- Existing menu commands open the same window on their corresponding section.
- Scanning occurs only after the user presses `Scan`.
- Scan rows have no batch-selection or `Add Selected` action.
- Checking an untracked candidate registers and enables it immediately.
- Unchecking a tracked candidate disables it immediately without deleting its
  recipe, approvals, or state.
- Rechecking a disabled candidate enables it immediately.
- New scan registrations remain untrusted and require the existing approval
  flow before commands can run.
- Persistent helper text is replaced by native tooltips and accessibility
  labels where the information is supplementary.
- Existing CLI output contracts and trust semantics do not change.

## Scope

### In Scope

- Dashboard navigation and routing.
- Embedding the current Scan UI in the Dashboard.
- Immediate per-row scan mutations.
- Reduced text density in Overview, Items, and Scan & Add.
- Dashboard, menu-model, adapter, documentation, and smoke-test updates required
  by the unified window.

### Out Of Scope

- Deleting registered items from Scan & Add.
- Automatically scanning when the section opens.
- Automatically approving discovered commands.
- Changing recipe detection or scan-result ordering.
- Adding or changing CLI stdout payloads.
- Redesigning the native menu-bar menu, Config panel, TUI, or CLI.

## Information Architecture

`DashboardPanelController` continues to own one reusable `NSWindow`. Replace its
top `NSTabViewController` navigation with a native split layout:

- A fixed-width sidebar lists `Overview`, `Items`, and `Scan & Add` with SF
  Symbols and text labels.
- A content container displays exactly one reusable child view controller.
- Selecting a sidebar row swaps the visible child without creating a window.
- The window title remains `Dashboard`.

Use a `DashboardSection` enum with `overview`, `items`, and `scan` cases as the
single routing type. The menu routes remain direct:

- `Dashboard` opens `.overview`.
- `Manage Items` opens `.items`.
- `Scan & Add` opens `.scan`.

Application activation behavior is unchanged: showing the Dashboard promotes
the accessory app to `.regular`, and closing the last visible titled window
returns it to `.accessory`.

## Visual Language

All three Dashboard sections follow the same compact rule: permanently show
only the section title, primary action, controls, and data needed to complete
the task.

Supplementary explanations move to native `.help` tooltips and VoiceOver labels.
Tooltips do not replace essential labels, error recovery, or table data.

### Overview

- Use `Overview` as the section title; remove the duplicate `UpdateBar` heading
  and the persistent sentence such as `Everything is up to date`.
- Metric tiles show an icon and compact value without a visible title.
- Each metric retains its full meaning and unabridged value in its tooltip and
  accessibility label.
- Dates may use compact visible forms such as a time or relative day count; the
  tooltip exposes the full formatted date.
- Keep the four-week chart and its existing accessibility chart descriptor, but
  remove redundant chart helper copy when the chart itself communicates the
  state. A genuinely empty or unavailable chart may retain a concise empty-state
  message.

### Items

- Use `Items` as the section title.
- Replace the visible `Refresh` label with a standard refresh icon button that
  has a tooltip and accessibility label.
- Remove persistent status copy such as `Ready`, `Loading`, and `12 item(s)`.
- Preserve table headers, category group labels, versions, status values, and
  enable checkboxes because they are task data rather than helper copy.
- Show an operation spinner or warning on the affected row instead of placing a
  running-status sentence above the table.

### Scan & Add

- Use `Scan & Add` as the section title and `Scan` as the only visible action
  label.
- Do not scan automatically.
- Do not show `Add Selected`.
- Show discovered, enabled, and disabled counts as compact number badges. Their
  meanings are available through tooltips and accessibility labels.
- Expose an info icon whose tooltip explains that unchecking disables a tracked
  item without deleting its settings or approvals.
- Preserve table headers and row state labels because they disambiguate an
  unchecked untracked row from an unchecked disabled row.

## Scan Row State Model

Convert `ScanPanelController` from an `NSWindowController` into a reusable
`ScanViewController`. Its presentation model represents each candidate as one
of these stable states:

- `untracked`: the candidate has a complete recipe but is not in the manifest.
- `enabled`: the candidate is registered and enabled.
- `disabled`: the candidate is registered and disabled.
- `unavailable`: the candidate cannot be imported because it has no complete
  recipe.

A row may additionally have a transient mutation state with its target value and
an optional redacted error. Transient state belongs to presentation logic and
does not alter the persisted model until the service call succeeds.

The checkbox mapping is:

| Current state | User action | Service operation | Result |
|---|---|---|---|
| `untracked` | Check | Register the one candidate with `replace: false` | `enabled` |
| `enabled` | Uncheck | `setEnabled(id:enabled:false)` | `disabled` |
| `disabled` | Check | `setEnabled(id:enabled:true)` | `enabled` |
| `unavailable` | Any | None; checkbox disabled | `unavailable` |

There is no checkbox path that calls `remove`. Registration continues through
`InitService`, which stores an untrusted copy and preserves UpdateBar's approval
boundary.

## Data Flow

1. The user opens `Scan & Add`; the Dashboard selects `.scan` but performs no
   scan.
2. The user presses `Scan`; the service returns candidates and the current
   status snapshot.
3. `ScanListModel` joins candidates with registered item enabled states to build
   stable rows and count badges.
4. The user changes one checkbox. Only that row becomes pending and is disabled
   while its service mutation runs on the background queue.
5. On success, the row adopts its target state. The Dashboard reloads Items and
   Overview data and asks the menu-bar app to refresh its menu state.
6. On failure, the row restores its previous checkbox state and exposes a
   redacted warning with native error presentation and an accessibility
   announcement.

Mutations are keyed by candidate ID. A second mutation for the same row is
blocked until the first finishes; unrelated rows remain interactive. `Scan` is
disabled while any row mutation is pending. A generation token rejects stale
scan completions after the window closes or a later scan begins.

## Service Boundary

Extend `MenuBarServicing` only as needed to obtain registered enabled state in
the scan presentation and to perform existing mutations. Reuse:

- `registerScannedCandidates` for untracked candidates.
- `setEnabled` for tracked candidates.
- `status(refresh: false)` for registered enabled state.

Do not expose `RegistryService.remove` through the menu-bar service for this
feature. Both `CoreMenuBarService` and the CLI fallback retain their current
trust and JSON contracts.

## Error Handling

- A scan failure leaves the last successful results visible, marks the Scan
  control as failed, and presents the existing redacted native error UI.
- A row mutation failure restores the prior state and shows a warning on that
  row. It must not change other rows or clear scan results.
- A refresh failure after a successful mutation does not roll back persisted
  state. The affected row remains in the known successful state, and the
  Dashboard exposes the refresh error separately.
- All user-derived names, paths, and error descriptions continue through
  `SecretRedactor` before display or logging.

## Accessibility

- Sidebar rows support keyboard selection and expose selected state.
- Icon-only buttons and number badges have meaningful accessibility labels and
  native tooltips.
- A scan-row checkbox label includes the candidate name and intended action.
- Pending row mutations expose a progress description without moving keyboard
  focus.
- Reverted mutations announce the redacted failure through native accessibility
  notification APIs.
- The existing chart descriptor remains the authoritative nonvisual chart
  representation.

## Documentation And Compatibility

Update `docs/menu-bar.md` to describe the single Dashboard window, sidebar
navigation, manual Scan action, and immediate tracking toggles. Remove language
that calls Scan & Add a separate panel.

This is a behavior-sized menu-bar change and therefore requires an OpenSpec
change entry before implementation unless Kendrick explicitly waives it.

## Verification

### Unit And Contract Tests

- `ScanListModel` maps untracked, enabled, disabled, unavailable, pending, and
  failure states correctly.
- Toggling an untracked row registers only that candidate and leaves its command
  approvals empty.
- Toggling enabled and disabled rows calls `setEnabled` with the correct value.
- A failed mutation restores the previous checkbox state.
- Two different rows can mutate independently, while a duplicate mutation for
  one ID is rejected.
- A newer scan generation rejects stale scan completion callbacks.
- Menu actions route Overview, Items, and Scan & Add into one Dashboard window.
- Source contracts prove that the standalone Scan panel and `Add Selected`
  control are removed.
- Tooltip and accessibility labels exist for compact metrics, counts, info, and
  icon-only refresh controls.

### Manual QA

- Open each Dashboard section from its native menu route and from the sidebar.
- Confirm that the same window is reused and sidebar keyboard navigation works.
- Confirm that opening Scan & Add does not start a scan.
- Scan, register a new candidate, disable it, and re-enable it without any batch
  action.
- Confirm that disabling preserves the recipe and approvals.
- Force scan, registration, enable, disable, and refresh failures and verify
  row-local recovery and redaction.
- Verify tooltips with pointer hover and labels with VoiceOver.
- Verify Dock and Cmd-Tab behavior while the window is visible and after it
  closes.

### Completion Gate

- Run targeted menu-bar model and source-contract tests while developing.
- Run `Scripts/quality-gate.sh` before claiming completion.
- Review `git diff --stat` to ensure only task-related files changed.
