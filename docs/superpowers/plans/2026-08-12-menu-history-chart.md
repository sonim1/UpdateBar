# Menu History Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the last 30 days of successful library updates in the Overview and the menu bar popover while removing the Installed section.

**Architecture:** Reuse `DashboardModel`'s successful-update daily buckets and expose a compact summary for the menu model. Render the Overview with an A-style titled chart card; render the menu model's chart entry through a native AppKit view so it remains compact and accessible.

**Tech Stack:** Swift 6, SwiftUI Charts, AppKit, XCTest.

---

### Task 1: Model the menu history summary

**Files:**
- Modify: `Sources/UpdateBarMenuBar/DashboardModel.swift`
- Modify: `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift`
- Test: `Tests/UpdateBarMenuBarTests/DashboardModelTests.swift`
- Test: `Tests/UpdateBarMenuBarTests/MenuBarMenuModelTests.swift`

- [ ] **Step 1: Add failing tests** for 30-day successful update totals and absence of `Installed` menu entries.
- [ ] **Step 2: Run targeted tests** and confirm their expected failures.
- [ ] **Step 3: Add the minimal `MenuBarUpdateHistory` model and menu entry.**
- [ ] **Step 4: Run targeted tests** and confirm passing output.

### Task 2: Render both chart surfaces

**Files:**
- Modify: `Sources/UpdateBarMenuBarApp/DashboardOverviewView.swift`
- Create: `Sources/UpdateBarMenuBarApp/MenuBarUpdateHistoryView.swift`
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`
- Test: `Tests/UpdateBarMenuBarTests/MenuBarUpdateHistoryViewTests.swift`

- [ ] **Step 1: Add failing renderer coverage** that checks bar normalization and the empty state.
- [ ] **Step 2: Run focused renderer tests** and confirm expected failure.
- [ ] **Step 3: Add the Overview A card and native AppKit menu history view.**
- [ ] **Step 4: Run focused renderer tests** and confirm passing output.

### Task 3: Verify and land

**Files:**
- Modify: relevant source and test files only.

- [ ] **Step 1: Run `swift test` and `git diff --check`.**
- [ ] **Step 2: Review the diff and resolve findings.**
- [ ] **Step 3: Commit, merge into `main`, push, then remove the feature and prior About worktrees.**
