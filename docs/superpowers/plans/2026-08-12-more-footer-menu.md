# More Footer Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group secondary menu-bar navigation under a `More` submenu.

**Architecture:** Reuse `MenuBarSubmenu` and the existing action enum. Keep the grouping entirely in the menu model so AppKit rendering needs no new behavior.

**Tech Stack:** Swift, XCTest, AppKit menu model

---

### Task 1: Footer grouping

**Files:**
- Modify: `Sources/UpdateBarMenuBar/MenuBarMenuAction.swift`
- Modify: `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift`
- Test: `Tests/UpdateBarMenuBarTests/MenuBarMenuModelTests.swift`

- [ ] **Step 1: Write failing model tests**

Assert that normal and error menus expose Dashboard, More, Check for Updates, and Quit at the top level, and that More contains Manage Items, Scan & Add, Settings, and About.

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter MenuBarMenuModelTests`

Expected: failures because secondary actions are still top-level and More is absent.

- [ ] **Step 3: Implement the minimum grouping**

Split the footer actions into primary and secondary arrays, then append the secondary array as one `MenuBarSubmenu(title: "More", ...)` in normal and error menus.

- [ ] **Step 4: Verify targeted and full tests**

Run: `swift test --filter MenuBarMenuModelTests`, then `swift test`, `swift format lint` for changed Swift files, and `git diff --check`.

- [ ] **Step 5: Commit and integrate**

Stage only the spec, plan, source, and test files. Commit, fast-forward main, rerun the full suite, push main, and inspect Automatic Release and Release workflow results.
