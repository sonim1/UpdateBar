# UpdateBar Native Menu Design

## Goal

Use the standard macOS status-item menu for fast status inspection and commands,
while keeping UpdateBar's polished Dashboard as a separate window for detailed
information.

## User Experience

- The existing UpdateBar icon and badge remain in the macOS menu bar.
- Clicking the status item opens the system `NSMenu`.
- Native menu items, separators, disabled states, submenus, application icons,
  checkmarks, keyboard navigation, and hover behavior follow macOS conventions.
- The menu summarizes current status and exposes updates, approvals, errors, and
  installed items without dashboard-style cards or custom navigation.
- `Dashboard` opens the existing standalone Dashboard window.
- Open TUI becomes a submenu when multiple supported terminals are installed;
  the selected terminal is checked and each terminal uses its application icon.
- Cancel Current Action replaces the normal action area while work is running.
- Destructive or trust-sensitive actions keep their existing confirmations.

## Architecture

### Status Item and Menu

`UpdateBarMenuBarApp` owns the `NSStatusItem` and assigns an `NSMenu` to
`statusItem.menu`. The status button has no custom target or action. A normal
rebuild creates `MenuBarMenuModel` from the latest state, approval data, active
action, last action notice, and terminal selection, then converts that model to
native AppKit menu items with `makeMenu(from:)`.

`MenuBarMenuModelBuilder` remains the single presentation source for normal and
error menus. Existing selector routing performs refreshes, updates, approvals,
terminal launches, panel presentation, and application commands.

### Dashboard

`DashboardPanelController` remains a standalone window controller. The native
`Dashboard` item keeps the internal `.overview` action and calls the existing
`showOverview()` route. Dashboard layout, charts, history, and management views
are outside the status menu.

### State and Actions

- Generation-gated refreshes prevent stale asynchronous results from replacing
  newer state.
- Action completion rebuilds the menu immediately before starting a follow-up
  refresh, so Running and Cancel Current Action disappear without delay.
- Status, approval, confirmation, redaction, and service behavior are unchanged.
- Refresh failures set the badge to `!` and directly assign the native recovery
  menu, which retains the Dashboard route and essential commands.

## Accessibility and Appearance

- Preserve the status button accessibility identifier and dynamic label.
- Rely on native AppKit menu focus, hover, keyboard, VoiceOver, light and dark
  appearance, and Reduce Transparency behavior.
- Keep useful tooltips and do not encode state by color alone.

## Testing

- Verify the status item owns a native menu and has no custom click routing.
- Verify normal and error rebuilds assign menus created by the shared builder.
- Verify `Dashboard` maps to `.overview` in normal and recovery menus.
- Keep model tests for menu content, confirmations, redaction, action state, and
  terminal selection.
- Keep refresh-generation and immediate action-completion regressions.
- Manually verify status-item opening, Dashboard presentation, keyboard
  navigation, confirmations, and terminal selection in the packaged app.

## Non-Goals

- Replacing or simplifying the standalone Dashboard.
- Changing model, service, update, approval, configuration, or CLI behavior.
- Customizing the macOS menu bar itself.
