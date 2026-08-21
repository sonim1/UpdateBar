# Dashboard Selected Updates Design

## Goal

Let users update one or several eligible items from the Dashboard's Items section without removing the existing Update All action.

The Items section will support both:

- an `Update` button on each eligible outdated row; and
- selection checkboxes with an `Update Selected (n)` action.

## Scope

This change covers the native macOS Dashboard, the menu-bar action coordinator, and the service adapters required to pass multiple explicit item IDs into the existing update engine.

It does not change update eligibility rules, approval semantics, bounded update parallelism, command execution, the Update All action, or the CLI's user-facing syntax.

## Eligibility

An item is selectable and exposes an enabled row-level Update button only when it is:

- outdated;
- enabled;
- not pinned; and
- approved for every required command field.

Rows that are current, disabled, pinned, checking, errored, or awaiting approval remain visible but cannot be selected or updated. Their disabled controls explain the reason with a tooltip and accessibility help text such as `Up to date`, `Disabled`, `Pinned`, or `Needs approval`.

The Dashboard derives this presentation state from the current `StatusItem` data. It does not maintain a second eligibility policy.

## Items Interface

The existing `On`, `Name`, `Current`, `Latest`, and `Status` columns remain. Two columns are added:

- `Select`: a checkbox for batch selection; and
- `Action`: a row-level `Update` button.

The Items header includes `Update Selected (n)`, where `n` is the number of selected eligible items. The button is disabled when `n` is zero or another action is running.

Selection starts empty whenever the Items view first loads. A status refresh, update completion, update failure, or explicit Items refresh clears the selection. Selection is not persisted between launches or snapshots.

The existing `On` checkbox remains solely responsible for enabling and disabling registered items. It is visually and behaviorally distinct from the new selection checkbox.

## User Interaction

Selecting an eligible row adds its stable item ID to the current selection. Deselecting it removes the ID.

Pressing a row's `Update` button starts an update with that row's single ID. Pressing `Update Selected (n)` starts one update action with exactly the selected IDs. Neither action displays an additional confirmation dialog, matching the existing per-item and Update All behavior.

While any update or other coordinated action is active, the Items view disables selection checkboxes, row Update buttons, the Update Selected button, enable/disable controls, and refresh. The existing action coordinator remains the source of truth for this global busy state.

## Architecture

`MenuBarServicing` gains an explicit multi-item update operation that accepts `[String]` plus the existing cancellation token, progress handler, and stop signal. The single-item convenience operation delegates to the multi-item operation with one ID.

`CoreMenuBarService` passes the IDs into the existing `UpdateRunner` with `all: false`. This preserves the existing eligibility validation, bounded parallel execution, progress events, partial success behavior, cancellation, and Stop After Current semantics.

`UpdateBarCLIClient` invokes the existing CLI update command with the explicit IDs followed by the established non-interactive JSON flags. It continues to document that subprocess mode cannot emit the in-process progress stream.

`ManageItemsViewController` owns only view-local selected IDs and emits update intents. It does not call update service methods directly. `DashboardPanelController` forwards those intents to `UpdateBarMenuBarApp`, which starts them through the existing `runAction` path. This keeps Dashboard updates synchronized with menu-bar updates and prevents concurrent actions.

The top-level app reports the action coordinator's busy state back to the Dashboard. The Items controller renders that state and does not create a separate action lock.

## Data Flow

1. Dashboard reload receives a `StatusSnapshot` and clears the current selection.
2. `ManageItemsModel` maps each `StatusItem` to a row presentation containing update eligibility and its disabled reason.
3. The user selects eligible row IDs or presses one row's Update button.
4. `ManageItemsViewController` emits the explicit IDs without executing commands.
5. `DashboardPanelController` forwards the intent to `UpdateBarMenuBarApp`.
6. `UpdateBarMenuBarApp` starts one coordinated action and calls `service.update(ids:)`.
7. The existing update engine emits per-item progress and honors cancellation or Stop After Current.
8. On success, partial failure, cancellation, or error, the app finishes the coordinated action and reloads status.
9. The refreshed snapshot clears selection and shows the actual current state of every item.

## Errors and Partial Success

Errors use the existing Dashboard error queue and secret redaction. The UI does not roll back items that already updated successfully when another selected item fails.

After every terminal outcome, status is reloaded. The Items table therefore reflects persisted update history and state rather than optimistic assumptions.

If an item becomes ineligible between selection and execution, the existing update engine remains authoritative and reports the result. The Dashboard does not bypass or duplicate that validation.

## Accessibility

Selection checkboxes expose `Select <item name>` or `Deselect <item name>`. Row buttons expose `Update <item name>`. Disabled controls expose the eligibility reason through both tooltip and accessibility help.

`Update Selected (n)` includes the selected count in its visible and accessibility labels. Keyboard users can reach both new columns through normal table traversal.

## Testing

Tests will verify:

- row presentation identifies eligible and ineligible statuses with stable disabled reasons;
- selection begins empty, toggles only eligible IDs, and clears on refresh and terminal outcomes;
- row Update emits one ID and Update Selected emits exactly the selected IDs;
- all Items mutation and refresh controls are disabled while the global action coordinator is busy;
- `CoreMenuBarService` passes multiple IDs to `UpdateRunner` with `all: false`;
- `UpdateBarCLIClient` constructs the existing CLI command with every explicit ID;
- single-item menu updates and Update All retain their current behavior;
- cancellation, partial failure, error presentation, and post-action reload remain intact;
- the macOS Dashboard target builds and the full Swift test suite passes.

## Success Criteria

- A user can update one eligible item directly from its Items row.
- A user can select several eligible items and start one coordinated update action.
- Ineligible items explain why they cannot be selected or updated.
- Dashboard and menu-bar actions cannot run concurrently.
- Existing update execution, progress, stop, approval, and Update All semantics are unchanged.
