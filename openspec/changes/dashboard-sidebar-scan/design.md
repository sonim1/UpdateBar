## Decisions

- Use one `NSSplitViewController` with a `DashboardSection` enum for Overview, Items, and Scan & Add navigation.
- Embed `ScanViewController` in the unified Dashboard window.
- Selecting Scan does not auto-scan; the visible Scan button invokes the existing scan service.
- Model stable scan-row states as untracked, enabled, disabled, and unavailable. An unavailable row has no complete recipe; its checkbox is disabled and no service call is made.
- Checking an untracked row calls `registerScannedCandidates` for one ID.
- Unchecking an enabled row calls `setEnabled(false)`.
- Checking a disabled row calls `setEnabled(true)`.
- No Scan interaction calls `remove`.
- Registration remains untrusted; disabling preserves recipe, approvals, state, and history.
- On every toggle, capture the previous and target state keyed by candidate ID. Immediately reflect the target control state, disable only that pending row, and show row-local progress. Reject a duplicate toggle for the same ID while it is pending; unrelated rows remain interactive.
- Disable the Scan button while any row mutation is pending. On success, keep the target state and trigger the shared Dashboard/menu refresh. On failure, restore the previous checkbox/state, show a redacted row-local warning, and present the native error.
- Manual scan remains explicit, and scan completions carry a generation token so stale results are rejected.
- Compact persistent copy keeps equivalent detail available through tooltips and accessibility labels.

## Scan controller refactor

- Convert the existing `ScanPanelController` into reusable `ScanViewController`, preserving and reusing its table and scan behavior.
- Remove `NSPanel` ownership and the old standalone source after embedding the reusable controller in the Dashboard window.

## Test seams

- Keep a pure `DashboardNavigationModel` seam for mapping Dashboard, Manage Items, and Scan & Add actions to `DashboardSection` without creating presentation state outside the model.
- Keep a pure `DashboardPresentationModel` seam for compact values and their complete metric, count-badge, information, and refresh tooltip/accessibility strings.
- Keep a `ScanSessionGenerationGate` seam that accepts the current manual-scan generation and invalidates it when the window closes, so stale completions can be rejected deterministically.

## Risks

- Per-ID race gating is needed when a row is toggled repeatedly while a mutation is in flight.
- Hiding helper text can reduce discoverability if tooltip and accessibility coverage is incomplete.
- A native sidebar makes the Dashboard window wider.

## Rollback

Rollback restores the old presentation without changing the data format.
