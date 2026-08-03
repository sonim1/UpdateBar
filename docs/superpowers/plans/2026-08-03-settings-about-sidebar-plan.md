# UpdateBar Settings And About Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SwitchTab-inspired Settings and About destinations to the existing UpdateBar sidebar, with a compact update queue in the sidebar footer while preserving the information-rich menu and Overview statistics.

**Architecture:** Keep `DashboardPanelController` as the single reusable window and extend its existing `DashboardSection` routing to Settings and About. Keep presentation data in the `UpdateBarMenuBar` target, host new SwiftUI content in focused macOS controllers/views, and derive the sidebar queue from the already refreshed `MenuBarState` without adding persistence or service calls.

**Tech Stack:** Swift 6, AppKit `NSWindowController`/`NSSplitViewController`/`NSTableView`, SwiftUI hosting, Sparkle 2, XCTest.

---

## File Map

- Modify `Sources/UpdateBarMenuBar/DashboardNavigationModel.swift`: add Settings/About routes and titles/icons.
- Modify `Sources/UpdateBarMenuBar/MenuBarMenuAction.swift`: expose Settings/About footer actions and user-facing titles.
- Create `Sources/UpdateBarMenuBar/SidebarUpdateQueueModel.swift`: pure, redacted, capped queue presentation model.
- Modify `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift`: keep the existing menu data unchanged; only reuse its redaction and state contracts where needed.
- Modify `Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift`: render the five-row sidebar plus the lower update queue card and route queue selections.
- Modify `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`: own Settings/About child controllers, pass refreshed state to the sidebar, and route queue selections to Overview.
- Modify `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`: route Settings/About from the native menu into the shared Dashboard window and remove direct config-panel ownership.
- Modify `Sources/UpdateBarMenuBarApp/ConfigPanelController.swift`: replace the standalone window controller with a reusable `SettingsViewController` that hosts SwiftUI while retaining existing config load/save service calls.
- Create `Sources/UpdateBarMenuBarApp/SettingsView.swift`: SwitchTab-inspired header, General group, and Sparkle Updates group.
- Create `Sources/UpdateBarMenuBarApp/AboutViewController.swift`: reusable About destination controller and support/acknowledgment actions.
- Create `Sources/UpdateBarMenuBarApp/AboutView.swift`: clean icon/version/description About presentation without statistics.
- Modify `Tests/UpdateBarMenuBarTests/DashboardNavigationModelTests.swift`: route and sidebar section coverage.
- Modify `Tests/UpdateBarMenuBarTests/MenuBarMenuActionTests.swift`: footer/error action coverage.
- Create `Tests/UpdateBarMenuBarTests/SidebarUpdateQueueModelTests.swift`: queue cap, overflow, empty state, redaction, and version display tests.
- Modify `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`: source contracts for native menu routing and no statistics in About.
- Modify `Tests/UpdateBarMenuBarTests/DashboardSidebarViewControllerTests.swift`: five-section and queue accessibility/routing contracts.
- Modify `docs/menu-bar.md`: document Settings/About sidebar routes and the sidebar update queue.

## Task 1: Lock the pure navigation and queue contracts with failing tests

**Files:**
- Test: `Tests/UpdateBarMenuBarTests/DashboardNavigationModelTests.swift`
- Test: `Tests/UpdateBarMenuBarTests/MenuBarMenuActionTests.swift`
- Create: `Tests/UpdateBarMenuBarTests/SidebarUpdateQueueModelTests.swift`
- Create: `Sources/UpdateBarMenuBar/SidebarUpdateQueueModel.swift`

- [ ] **Step 1: Add failing navigation tests.** Add tests asserting `DashboardSection.allCases` is `[.overview, .items, .scan, .settings, .about]`, titles are `Overview`, `Items`, `Scan & Add`, `Settings`, `About`, and `DashboardNavigationModel.section(for:)` maps `.openConfig` to `.settings` and `.about` to `.about`.

- [ ] **Step 2: Add failing menu action tests.** Assert `MenuBarMenuAction.about` exists, has title `About UpdateBar`, `.openConfig` has title `Settings...`, and both actions appear before `.viewLogs`, `.checkForUpdates`, and `.quit` in `footer` and `errorRecovery`.

- [ ] **Step 3: Add failing queue tests.** Define the expected public API in tests:

```swift
let queue = SidebarUpdateQueueModel.make(
    outdatedItems: [item("node", current: "20", latest: "22")],
    limit: 3
)
XCTAssertEqual(queue.count, 1)
XCTAssertEqual(queue.items.first?.title, "node")
XCTAssertEqual(queue.items.first?.versionChange, "20 → 22")
XCTAssertEqual(queue.overflowCount, 0)
```

Also cover four items (`items.count == 3`, `overflowCount == 1`), an empty input (`isVisible == false`), and names containing a home path or command text being redacted through `SecretRedactor`.

- [ ] **Step 4: Run only the new tests to confirm RED.**

Run: `rtk test swift test --filter 'DashboardNavigationModelTests|MenuBarMenuActionTests|SidebarUpdateQueueModelTests'`

Expected: compile/test failure because Settings/About cases and `SidebarUpdateQueueModel` do not yet exist.

- [ ] **Step 5: Commit the test-only RED checkpoint.**

```bash
rtk git add Tests/UpdateBarMenuBarTests/DashboardNavigationModelTests.swift Tests/UpdateBarMenuBarTests/MenuBarMenuActionTests.swift Tests/UpdateBarMenuBarTests/SidebarUpdateQueueModelTests.swift
rtk git commit -m "test: specify settings about sidebar routes"
```

## Task 2: Implement navigation actions and the pure queue model

**Files:**
- Modify: `Sources/UpdateBarMenuBar/DashboardNavigationModel.swift`
- Modify: `Sources/UpdateBarMenuBar/MenuBarMenuAction.swift`
- Create: `Sources/UpdateBarMenuBar/SidebarUpdateQueueModel.swift`

- [ ] **Step 1: Add Settings/About section cases.** Extend `DashboardSection` with `.settings` and `.about`, titles `Settings`/`About`, and SF Symbols `gearshape`/`info.circle`. Keep the existing first three case order unchanged so current sidebar selection tests remain stable.

- [ ] **Step 2: Add menu actions and route mappings.** Add `.about`; rename only the visible `.openConfig` title to `Settings...`; append `.about` to the footer/error-recovery lists; map `.openConfig` and `.about` in `DashboardNavigationModel.section(for:)`.

- [ ] **Step 3: Implement the queue model.** Add `SidebarUpdateQueueItem(title:versionChange:)` and `SidebarUpdateQueue(count:items:overflowCount)` as `Equatable, Sendable` values. `SidebarUpdateQueueModel.make` must take `outdatedItems` and `limit`, redact item names/version strings with `SecretRedactor`, keep the first `limit` items, and compute `overflowCount` without calling the service.

- [ ] **Step 4: Run the focused tests GREEN.**

Run: `rtk test swift test --filter 'DashboardNavigationModelTests|MenuBarMenuActionTests|SidebarUpdateQueueModelTests'`

Expected: all focused tests pass.

- [ ] **Step 5: Commit the model layer.**

```bash
rtk git add Sources/UpdateBarMenuBar/DashboardNavigationModel.swift Sources/UpdateBarMenuBar/MenuBarMenuAction.swift Sources/UpdateBarMenuBar/SidebarUpdateQueueModel.swift Tests/UpdateBarMenuBarTests
rtk git commit -m "feat: add settings about sidebar routes"
```

## Task 3: Add the sidebar update queue and shared-window destinations

**Files:**
- Modify: `Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift`
- Modify: `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`
- Modify: `Tests/UpdateBarMenuBarTests/DashboardSidebarViewControllerTests.swift`

- [ ] **Step 1: Add failing controller contracts.** Assert the sidebar exposes five section labels, selected state is retained for `.settings` and `.about`, and a queue row callback receives `.overview` plus the selected item identifier. Keep the existing source-list accessibility label `Dashboard sections`.

- [ ] **Step 2: Build the sidebar footer layout.** Wrap the current source-list scroll view and a new queue `NSView` in a vertical `NSStackView`. Give the navigation region a low hugging priority so the queue stays at the bottom. Render `Updates available`, count, up to three rows, and `and N more`; use redacted strings and accessibility labels from `SidebarUpdateQueue`.

- [ ] **Step 3: Add queue selection callback.** Add `var onUpdateSelected: (String) -> Void` to the sidebar controller. A queue row must not execute an update; it invokes the callback with the item ID so the dashboard selects `.overview` and lets the existing Overview action list handle execution.

- [ ] **Step 4: Add Settings/About child controllers.** In `DashboardPanelController`, create reusable `SettingsViewController` and `AboutViewController` child instances, include them in `controller(for:)`, and update `select`/`showContent` to handle the new sections. Pass a refreshed `SidebarUpdateQueueModel.make(outdatedItems: latestState.outdatedItems)` to the sidebar from `apply` and from initial state.

- [ ] **Step 5: Wire queue routing and refresh behavior.** The sidebar callback selects `.overview`, calls `showContent`, and leaves `latestState` unchanged. `reload()` must continue refreshing Overview, Items, and Scan; queue updates whenever `apply` receives a new snapshot.

- [ ] **Step 6: Run focused sidebar tests and compile.**

Run: `rtk test swift test --filter 'DashboardSidebarViewControllerTests|DashboardNavigationModelTests|SidebarUpdateQueueModelTests'`

Expected: all selected tests pass and the macOS target compiles.

- [ ] **Step 7: Commit the shared-window/sidebar work.**

```bash
rtk git add Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift Sources/UpdateBarMenuBarApp/DashboardPanelController.swift Tests/UpdateBarMenuBarTests/DashboardSidebarViewControllerTests.swift
rtk git commit -m "feat: add update queue to dashboard sidebar"
```

## Task 4: Replace Config with SwitchTab-inspired Settings content

**Files:**
- Modify: `Sources/UpdateBarMenuBarApp/ConfigPanelController.swift`
- Create: `Sources/UpdateBarMenuBarApp/SettingsView.swift`
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`

- [ ] **Step 1: Add failing Settings source contracts.** Add source tests asserting the Settings view contains `General`, `Updates`, `Check for Updates`, `Refresh interval`, and `Require HTTPS sources`, and that it does not add a second update service path.

- [ ] **Step 2: Create the SwiftUI Settings view.** Define `SettingsView` with an observable view model backed by `MenuBarServicing`, the existing `SPUStandardUpdaterController` callback, and the app bundle version. Render a compact header with UpdateBar icon/name and a readiness pill, a grouped General card for the existing config fields, and an Updates card for version/check/automatic-check controls. Keep Save/Reload and redacted errors in the controller boundary.

- [ ] **Step 3: Host Settings in a reusable view controller.** Preserve the service's `loadConfig`/`saveConfig` calls, but replace the standalone `ConfigPanelController` window with a `SettingsViewController: NSViewController` that embeds an `NSHostingController<SettingsView>`. Keep loading, saving, and redacted error callbacks in this controller; the shared Dashboard owns its lifetime and window activation.

- [ ] **Step 4: Route menu Settings into the shared Dashboard.** Remove the direct `configPanelController` property and `openConfig` panel path from `UpdateBarMenuBarApp`; `showDashboard(for:)` must route `.openConfig` through `DashboardNavigationModel` to `.settings`. Keep Sparkle's existing `checkForUpdates` selector and updater controller.

- [ ] **Step 5: Run Settings source-contract tests.**

Run: `rtk test swift test --filter 'SourceHygieneTests|DashboardNavigationModelTests|MenuBarMenuActionTests'`

Expected: all selected tests pass; no existing config service contract changes.

- [ ] **Step 6: Commit Settings.**

```bash
rtk git add Sources/UpdateBarMenuBarApp/ConfigPanelController.swift Sources/UpdateBarMenuBarApp/SettingsView.swift Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift Tests/UpdateBarMenuBarTests
rtk git commit -m "feat: add switchtab inspired settings panel"
```

## Task 5: Add the clean About screen

**Files:**
- Create: `Sources/UpdateBarMenuBarApp/AboutViewController.swift`
- Create: `Sources/UpdateBarMenuBarApp/AboutView.swift`
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`

- [ ] **Step 1: Add failing About contracts.** Assert source contains UpdateBar name/version/icon/support/acknowledgment content and does not reference `DashboardSummary`, `DashboardMetric`, charts, or usage counters.

- [ ] **Step 2: Implement AboutView.** Create a SwiftUI view with a large app icon, product name, short local-update-tracking description, version/build lines from `Bundle.main`, and bottom `Contact Support`/`Acknowledgments` buttons. Use a neutral high-contrast background, no statistics, and omit empty optional build labels.

- [ ] **Step 3: Implement AboutViewController.** Host `AboutView` in a reusable `NSViewController` matching the Settings content lifecycle. Support opens `mailto:support@updatebar.royjen.com`; Acknowledgments presents a concise native alert listing Swift, AppKit, Sparkle, and UpdateBar components.

- [ ] **Step 4: Route About from the menu and sidebar.** Add `.about` to the menu selector switch and pass `.about` through `DashboardPanelController`; opening About must reuse the same Dashboard window, not create a second top-level window.

- [ ] **Step 5: Run About/source-hygiene tests.**

Run: `rtk test swift test --filter 'SourceHygieneTests|DashboardNavigationModelTests|MenuBarMenuActionTests'`

Expected: all selected tests pass and About has no statistics dependency.

- [ ] **Step 6: Commit About.**

```bash
rtk git add Sources/UpdateBarMenuBarApp/AboutViewController.swift Sources/UpdateBarMenuBarApp/AboutView.swift Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift
rtk git commit -m "feat: add clean about panel"
```

## Task 6: Update documentation and run the complete verification gate

**Files:**
- Modify: `docs/menu-bar.md`
- Modify: `Tests/UpdateBarMenuBarTests/DashboardSidebarViewControllerTests.swift`
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`

- [ ] **Step 1: Document the final information architecture.** Update `docs/menu-bar.md` so it describes the five-row sidebar, the lower update queue, Settings' app-update section, About's product-only content, and Overview as the sole statistics surface. Remove only stale wording that calls Config/About separate unrelated panels.

- [ ] **Step 2: Run targeted menu-bar tests.**

Run: `rtk test swift test --filter 'UpdateBarMenuBarTests'`

Expected: all menu-bar tests pass.

- [ ] **Step 3: Run formatting and shell/source checks.**

Run: `rtk git diff --check && rtk proxy bash -n Scripts/*.sh`

Expected: exit code 0 and no whitespace or shell syntax errors.

- [ ] **Step 4: Run the full quality gate.**

Run: `rtk test Scripts/quality-gate.sh`

Expected: exit code 0 and the final build reports `Build of product 'updatebar' complete!`.

- [ ] **Step 5: Perform manual macOS QA.** Launch the menu-bar app from the built product, open Settings/About/Overview/Manage Items/Scan & Add from both menu and sidebar, confirm one-window reuse, verify the queue routes to Overview, save/reload a config value, trigger Sparkle check, inspect About support/ack actions, and close the window to confirm accessory activation returns.

- [ ] **Step 6: Review and commit documentation/verification changes.**

```bash
rtk git diff --stat origin/main...HEAD
rtk git status --short
rtk git add docs/menu-bar.md Tests/UpdateBarMenuBarTests
rtk git commit -m "test: verify settings about sidebar experience"
```

## Execution Notes

- Preserve the existing native menu-bar model and all UpdateBarCore/service
  boundaries.
- Do not add a second polling loop for the sidebar queue.
- Use `SecretRedactor` before putting item names, versions, or errors into any
  visible UI or logs.
- Keep each task commit independently buildable; run the focused test command
  before moving to the next task.
