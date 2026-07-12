# UpdateBar Menubar Popover Design

## Goal

Modernize the menu bar experience using CodexBar as a visual reference while preserving UpdateBar's existing status item, actions, and separate dashboard window.

## User Experience

- The existing UpdateBar icon and badge remain in the macOS menu bar.
- A primary click opens a compact custom popover anchored to the status item.
- The popover uses macOS system material and vibrancy. It follows light mode, dark mode, and Reduce Transparency automatically.
- The popover has three views: Overview, Updates, and Approvals.
- Overview shows the last check time, tracked item count, update count, approval count, and error count.
- Updates and Approvals show compact actionable rows derived from the current menu bar state.
- The command area exposes Open Dashboard, Manage Items, Open TUI, Refresh, Settings, About, and Quit.
- Open Dashboard closes the popover and opens the existing standalone dashboard window.

The popover is intentionally compact. Charts, history, and detailed management remain in the dashboard or existing panels.

## Architecture

### Status Item Integration

`UpdateBarMenuBarApp` keeps ownership of `NSStatusItem`. Instead of assigning the primary menu to `statusItem.menu`, the status button invokes a popover controller. The existing `NSMenu` builder remains available only as an error fallback.

### Popover Controller

A focused controller owns popover presentation, anchoring, dismissal, and SwiftUI hosting. It uses AppKit system material through `NSVisualEffectView`, avoiding hard-coded translucency values.

The controller receives immutable presentation state and action closures. It does not call the service directly.

### Presentation Model

A small presentation model maps the existing `MenuBarState`, approval statuses, active action, and last action notice into:

- summary metrics;
- update rows;
- approval rows;
- enabled and disabled action states;
- loading, error, and empty states.

The existing service and action coordinator remain the source of truth. No new persistence or background process is introduced.

### Dashboard

`DashboardPanelController` remains a standalone window controller. The popover's Open Dashboard action calls the existing `showOverview()` path after dismissing the popover.

## Interaction Rules

- Clicking the status item toggles the popover.
- Clicking outside, pressing Escape, or invoking a command closes it.
- Keyboard focus follows macOS conventions for tabs, rows, and commands.
- Refresh and long-running actions reuse the existing action coordinator and confirmation dialogs.
- State refresh updates both the status badge and visible popover content.
- Popover positioning uses the status button as its anchor and remains on the active screen.

## Error Handling

- Service errors continue to set the status badge to `!`.
- When the popover is available, it presents a redacted error state with Refresh and Settings actions.
- If popover construction fails, UpdateBar falls back to the existing native error menu so the app remains operable.
- Existing secret redaction and confirmation behavior remain unchanged.

## Accessibility

- Preserve the status button accessibility label and identifier.
- Provide labels for tabs, status indicators, rows, and icon-only controls.
- Do not encode update, approval, or error state by color alone.
- Respect system appearance, Reduce Transparency, keyboard navigation, and VoiceOver.

## Testing

- Unit-test presentation-model mapping for updates, approvals, errors, empty state, and active actions.
- Unit-test command dispatch from popover actions to existing menu bar actions.
- Keep existing menu model and dashboard tests passing.
- Add focused controller tests where AppKit behavior is practical, including toggle and dismissal state.
- Manually verify light and dark modes, Reduce Transparency, keyboard navigation, outside-click dismissal, and positioning near screen edges.

## Non-Goals

- Customizing the macOS menu bar itself.
- Replacing the standalone dashboard with the popover.
- Adding charts or history to the popover.
- Changing update execution, approval semantics, configuration storage, or CLI behavior.
