# Menu Bar Logs and Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete per-item update feedback, remove the menu-bar TUI entry, and make persisted update/check history visible in a Dashboard Logs section.

**Architecture:** Keep scheduling/progress in UpdateBarCore and menu presentation in UpdateBarMenuBar. Add a small read-only AppKit controller for `HistoryEvent` display, route the legacy action through DashboardNavigationModel, and rebuild the existing ICNS from a transparent PNG.

**Tech Stack:** Swift 6, AppKit, SwiftUI hosting, XCTest, ImageGen.

---

### Task 1: Menu and Dashboard contracts

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/MenuBarMenuActionTests.swift`
- Modify: `Tests/UpdateBarMenuBarTests/DashboardNavigationModelTests.swift`
- Modify: `Sources/UpdateBarMenuBar/MenuBarMenuAction.swift`
- Modify: `Sources/UpdateBarMenuBar/DashboardNavigationModel.swift`

- [ ] Write failing tests for TUI/View Logs omission and Logs navigation.
- [ ] Run the focused tests and verify they fail because those contracts do not exist.
- [ ] Remove the two footer entries, add `DashboardSection.logs`, and map the legacy action to it.
- [ ] Re-run focused tests.

### Task 2: Dashboard history presentation

**Files:**
- Create: `Sources/UpdateBarMenuBar/HistoryLogPresentation.swift`
- Create: `Sources/UpdateBarMenuBarApp/LogsViewController.swift`
- Modify: `Tests/UpdateBarMenuBarTests/HistoryLogPresentationTests.swift`
- Modify: `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`

- [ ] Write failing tests for newest-first human-readable update/check log rows and empty history.
- [ ] Run the focused tests and verify failure.
- [ ] Implement the minimal presentation model and native table/empty view, apply history during Dashboard reload, and route `View Logs` to Dashboard.
- [ ] Re-run focused tests.

### Task 3: Transparent app icon

**Files:**
- Modify: `Assets/AppIcon/UpdateBar.png`
- Modify: `Assets/AppIcon/UpdateBar.icns`
- Test: `Scripts/app-icon-test.sh`

- [ ] Edit the existing artwork with ImageGen, preserving the icon and making the outer canvas removable chroma-key.
- [ ] Convert the chroma key to alpha, validate transparent corners, and rebuild ICNS with `Scripts/build-app-icon.sh`.
- [ ] Run the icon asset check and packaging smoke test.

### Task 4: Release validation

**Files:**
- Modify: `docs/menu-bar.md`

- [ ] Update user-facing menu-bar documentation to reflect TUI removal and Dashboard Logs.
- [ ] Run the full Swift suite, quality gate, and packaged-app smoke tests.
- [ ] Review the complete diff, resolve all review findings, merge to main, bump release metadata, push, and verify the release workflow.
