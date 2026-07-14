# Dashboard Popover Design

## Goal

Keep UpdateBar's primary status-item interaction as a system `NSMenu`, while opening a compact, read-only dashboard popover when the user chooses `Dashboard` from that menu.

## User Experience

- Clicking the UpdateBar status item opens the native macOS menu.
- Choosing `Dashboard` closes the menu and opens a transient popover anchored to the UpdateBar status item.
- The popover uses macOS system popover material and contains `Overview`, `Updates`, and `Approvals` views.
- Overview shows compact counts, current health, recent action state, and errors without dashboard cards or command grids.
- Updates and Approvals are read-only lists. Update, approval, refresh, settings, and quit commands remain in the native menu.
- An icon-only `Open Full Dashboard` control opens the existing detailed Dashboard window and closes the popover.

## Architecture

### Native Menu

`UpdateBarMenuBarApp` continues assigning `statusItem.menu` from `MenuBarMenuModel`. The status button receives no custom target or click action. The existing loading, active-action, cancellation, error-recovery, confirmation, and generation-gating behavior remains unchanged.

### Dashboard Presentation Model

`DashboardPopoverModel` is immutable, `Equatable`, and `Sendable`. A builder maps the latest `MenuBarState`, approval statuses, active-action state, last-action notice, and redacted error text into summary counts and read-only rows. It contains no mutation actions or confirmation payloads.

### Dashboard Popover

`DashboardPopoverView` is a 340-point-wide SwiftUI view with a compact header, native segmented picker, scrollable read-only rows, and an icon-only full-dashboard control. `DashboardPopoverController` owns one transient `NSPopover`, hosts the view inside `NSVisualEffectView(material: .popover)`, and anchors it to `NSStatusBarButton`.

### Integration

The existing `.overview` native-menu action invokes `showDashboardPopover()`. Presentation is dispatched to the next main-loop turn so the `NSMenu` closes before the popover opens. The controller receives an `onOpenFullDashboard` closure that closes the popover and calls the existing `showOverview()` window path.

Visible popover content updates after refresh, action completion, and errors. The popover never replaces or owns `statusItem.menu`.

## Error And State Rules

- Errors remain redacted before entering the model.
- A visible popover shows the latest error state without replacing the native recovery menu.
- Active actions appear as read-only status. Cancellation remains available only from the native menu.
- Stale refresh results remain blocked by `MenuBarRefreshGenerationGate`.
- If the status button is unavailable, Dashboard falls back to the existing full Dashboard window.

## Accessibility

- The segmented picker exposes Overview, Updates, and Approvals labels.
- Counts and rows combine title, detail, and state into VoiceOver labels.
- The full-dashboard icon has a label and tooltip.
- Status is never communicated by color alone.

## Testing

- Unit-test model mapping, redaction, empty states, errors, and active-action state.
- Add source-contract tests proving the status item still owns a native `NSMenu` and only the Dashboard action presents the popover.
- Build the AppKit target and keep all menu-model, refresh-generation, Dashboard, and documentation tests passing.
- Manually verify native menu dismissal, popover anchoring, outside-click dismissal, full-dashboard opening, keyboard traversal, light/dark appearance, and Reduce Transparency.

## Non-Goals

- Replacing the native menu with a popover.
- Running updates, approvals, refresh, configuration, or cancellation from the popover.
- Moving the detailed four-week chart into the compact popover.
- Changing service, persistence, CLI, or approval semantics.
