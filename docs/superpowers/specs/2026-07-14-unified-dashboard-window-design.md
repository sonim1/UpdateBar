# Unified Dashboard Window Design

## Goal

Replace the compact Dashboard popover and standalone Manage Items panel with one
native Dashboard window. The window must open directly from the native menu,
contain Overview and Items tabs, and appear in the macOS application switcher
while visible.

This design supersedes the compact-popover behavior documented in
`2026-07-13-dashboard-popover-design.md`.

## User Flow

- Clicking the status item continues to open the native `NSMenu`.
- Choosing `Dashboard` opens the Dashboard window directly on `Overview`.
- Choosing `Manage Items` opens the same Dashboard window directly on `Items`.
- Switching tabs never creates another window or panel.
- Closing the last visible titled UpdateBar window returns the process to its
  menu-bar-only activation policy.

## Window Architecture

`DashboardPanelController` owns one reusable `NSWindow` and one native
`NSTabViewController` using toolbar-style tabs. The Overview tab hosts the
existing SwiftUI metrics and four-week chart. The Items tab embeds the existing
AppKit table after converting `ManageItemsPanelController` into a reusable
`ManageItemsViewController`.

The Dashboard header no longer contains a Manage Items button. The tab control
is the only in-window navigation between Overview and Items.

## Routing

`MenuBarMenuAction.overview` routes to `showOverview`, and
`MenuBarMenuAction.manageItems` routes to `manageItems`. Both methods call a
shared `showDashboard(tab:)` helper. No status-button target/action is added;
`statusItem.menu` remains the primary native menu.

All `DashboardPopover*` sources, presentation state, menu tracking delegate
logic, and focused tests are removed because there is no popover path.

## Application Switcher

The process starts as `.accessory`. Before the Dashboard window is shown, the
app changes to `.regular` and activates, making the open window available in
Cmd-Tab/Alt-Tab and the Dock. `DashboardPanelController` reports window close.
On the next main-loop turn, the app returns to `.accessory` only when no visible
titled UpdateBar window remains.

## Data And Errors

Opening the Dashboard reloads both Overview and Items so either tab is ready
without another panel. Item toggles retain the existing background service call,
redaction, status feedback, and menu refresh callback. Overview history and
error presentation retain current behavior.

## Verification

- Source contracts prove direct routing, one tabbed Dashboard window, removed
  popover files, embedded Items controller, and activation-policy transitions.
- Existing menu race, cancellation, model, documentation, packaging, and smoke
  tests remain green.
- Manual QA covers both menu routes, tab switching, item toggles, one-window
  reuse, Cmd-Tab visibility while open, and return to menu-bar-only mode on
  close.
