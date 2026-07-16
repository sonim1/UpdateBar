# Unified Dashboard Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open one tabbed Dashboard window directly from the native menu, embed item management, and expose the app in Cmd-Tab only while a titled window is visible.

**Architecture:** `DashboardPanelController` owns a toolbar-style `NSTabViewController` with SwiftUI Overview and reusable AppKit Items content. The app delegate routes both native menu entries into that controller and switches activation policy around window visibility. Compact popover code is deleted.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Charts, XCTest, macOS 13+

---

### Task 1: Add Unified Window Contracts

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`

- [ ] Replace popover contracts with assertions that all `DashboardPopover*`
  files are absent.
- [ ] Assert the Dashboard controller defines `DashboardTab`, uses one
  `NSTabViewController` with `Overview` and `Items`, embeds
  `ManageItemsViewController`, and contains no Manage Items button.
- [ ] Assert Overview and Manage Items menu actions call the same Dashboard
  window helper with different tabs, no `NSMenuDelegate` remains, and
  `statusItem.menu` ownership is unchanged.
- [ ] Assert `.regular` is selected before showing the Dashboard and `.accessory`
  is restored after its close only when no visible titled windows remain.
- [ ] Run `rtk test swift test --filter SourceHygieneTests` and verify RED from
  the current popover routing and standalone panel architecture.

### Task 2: Embed Items In Dashboard

**Files:**
- Modify: `Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift`
- Modify: `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`

- [ ] Convert `ManageItemsPanelController` from `NSWindowController` into
  `ManageItemsViewController: NSViewController` while preserving table data,
  refresh, toggle, status, redaction, and error behavior.
- [ ] Add `DashboardTab` with `overview` and `items` cases.
- [ ] Build one toolbar-style `NSTabViewController`; host `DashboardView` in the
  Overview item and `ManageItemsViewController` in the Items item.
- [ ] Remove the Overview header's Manage Items button and callback.
- [ ] Add `showWindowAndReload(selecting:)`; select the requested tab, reuse the
  same window, and reload Overview and Items.
- [ ] Run `rtk test swift test --filter SourceHygieneTests` and
  `rtk err swift build --target UpdateBarMenuBarApp`.

### Task 3: Route Directly And Manage Activation Policy

**Files:**
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`
- Delete: `Sources/UpdateBarMenuBar/DashboardPopoverModel.swift`
- Delete: `Sources/UpdateBarMenuBarApp/DashboardPopoverController.swift`
- Delete: `Sources/UpdateBarMenuBarApp/DashboardPopoverView.swift`
- Delete: `Tests/UpdateBarMenuBarTests/DashboardPopoverModelTests.swift`

- [ ] Remove popover state, controller, `NSMenuDelegate`, pending-menu tracking,
  error synchronization, and presentation helpers.
- [ ] Add `showDashboard(tab:)`; create one Dashboard controller, switch to
  `.regular`, show the requested tab, and refresh menu state after item changes.
- [ ] Route Dashboard to `.overview` and Manage Items to `.items`.
- [ ] Observe native window-close notifications, defer a visible-titled-window
  check, and restore `.accessory` only when none remain.
- [ ] Run `rtk test swift test --filter UpdateBarMenuBarTests`, build the app,
  lint changed Swift files strictly, and run `rtk git diff --check`.

### Task 4: Documentation And Release Verification

**Files:**
- Modify: `docs/menu-bar.md`
- Modify: `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift`

- [ ] Document direct Dashboard-window routing, Overview/Items tabs, removed
  popover/panel, and Cmd-Tab visibility while the window is open.
- [ ] Run `rtk test swift test`.
- [ ] Run `rtk err swift build -c release --product updatebar-menubar`.
- [ ] Run strict `swift-format` over every changed Swift file and
  `rtk git diff --check`.
- [ ] Run `rtk err Scripts/package-app.sh` and
  `rtk err Scripts/menubar-smoke-test.sh dist/UpdateBar.app`.
- [ ] Relaunch the packaged app and visually verify both tabs and one-window
  behavior.
