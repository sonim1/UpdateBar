# Native Menubar Implementation Plan

**Goal:** Restore the system `NSMenu` as UpdateBar's primary status-item UI and
keep the existing Dashboard as a separate window.

**Architecture:** `UpdateBarMenuBarApp` builds a `MenuBarMenuModel` from current
state and action data, converts it to AppKit menu items, and assigns it to the
`NSStatusItem`. The existing `.overview` selector opens the Dashboard. No custom
status-button target, SwiftUI menu view, or popover controller remains.

**Tech Stack:** Swift 6, AppKit, XCTest, macOS 13+

## File Map

- Modify `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`: restore native
  menu ownership and native recovery-menu assignment.
- Modify `Sources/UpdateBarMenuBar/MenuBarMenuAction.swift`: display
  `.overview` as `Dashboard`.
- Delete the popover view, controller, presentation model, and model tests.
- Update focused source-hygiene and menu-model tests.
- Update menu bar documentation and documentation snapshots.
- Preserve Dashboard source files without modification.

## Task 1: Lock the Native Menu Contract

- [x] Add a focused source regression proving the status button has no custom
  target/action and normal rebuild assigns `makeMenu(from:)` to
  `statusItem.menu`.
- [x] Cover direct native recovery-menu assignment in `showError`.
- [x] Cover deletion of popover-only production and test files.
- [x] Add normal and error route assertions for `Dashboard -> .overview`.
- [x] Run the focused tests against the old implementation and record RED.

## Task 2: Restore Native AppKit Routing

- [x] Remove custom status-button click routing.
- [x] Build the normal menu with `MenuBarMenuModelBuilder` using latest state,
  approvals, action state, notices, and terminal selection.
- [x] Assign the converted native menu to `statusItem.menu` on every rebuild.
- [x] Assign the native error model directly after redacting refresh errors.
- [x] Keep all existing selectors, confirmations, icons, checkmarks, submenus,
  refresh generation gating, and immediate completion rebuild behavior.

## Task 3: Remove Dead Presentation Code

- [x] Delete `MenuBarPopoverView.swift`.
- [x] Delete `MenuBarPopoverController.swift`.
- [x] Delete `MenuBarPopoverModel.swift` and its tests.
- [x] Remove popover-only source-hygiene assertions and startup errors.

## Task 4: Align Documentation

- [x] Describe primary status-item clicks as opening native `NSMenu`.
- [x] Document the separate Dashboard window and `.overview` route.
- [x] Update documentation snapshot expectations.
- [x] Remove claims about custom tabs, dimensions, material, or fallback-only
  native menus.

## Task 5: Verify and Commit

- [x] Run focused menu and source-hygiene tests.
- [x] Run full `swift test`.
- [x] Build `updatebar-menubar` in release mode.
- [x] Run strict `swift-format` lint on changed Swift files.
- [x] Run `git diff --check` and self-review the complete branch diff.
- [x] Commit the architecture change with a clear message.

## Manual QA

- Clicking the status item opens a standard macOS menu.
- Update, approval, error, disabled, and running states render correctly.
- Dashboard opens the existing standalone window.
- Open TUI selection, confirmations, refresh, cancellation, and recovery actions
  still route correctly.
- VoiceOver, keyboard navigation, light/dark appearance, and status-item labels
  follow native behavior.
