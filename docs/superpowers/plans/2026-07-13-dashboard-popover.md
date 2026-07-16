# Dashboard Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open a compact read-only Dashboard popover from the native `NSMenu` while preserving the menu as the primary status-item UI and retaining the detailed Dashboard window.

**Architecture:** A pure `DashboardPopoverModelBuilder` maps current menu-bar state into read-only presentation data. `DashboardPopoverController` hosts a SwiftUI dashboard in a transient system-material `NSPopover` anchored to the existing status button. The `.overview` native-menu selector presents this popover; an icon inside it invokes the existing full Dashboard window.

**Tech Stack:** Swift 6, AppKit, SwiftUI, XCTest, macOS 13+

---

## File Map

- Create `Sources/UpdateBarMenuBar/DashboardPopoverModel.swift`: immutable read-only presentation model and builder.
- Create `Tests/UpdateBarMenuBarTests/DashboardPopoverModelTests.swift`: summary, row, error, redaction, and active-state tests.
- Create `Sources/UpdateBarMenuBarApp/DashboardPopoverView.swift`: compact segmented dashboard surface.
- Create `Sources/UpdateBarMenuBarApp/DashboardPopoverController.swift`: transient `NSPopover` lifecycle and system material.
- Modify `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`: Dashboard menu routing, live model updates, full-window callback, fallback.
- Modify `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`: native-menu ownership and Dashboard-only popover contracts.
- Modify `docs/menu-bar.md` and `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift`: final behavior documentation.

### Task 1: Build The Read-Only Dashboard Model

**Files:**
- Create: `Sources/UpdateBarMenuBar/DashboardPopoverModel.swift`
- Create: `Tests/UpdateBarMenuBarTests/DashboardPopoverModelTests.swift`

- [ ] **Step 1: Write failing model tests**

Cover counts, last checked, read-only update/approval/error rows, active action, last action, error redaction, and empty state. Assert the row type has no action or confirmation fields.

```swift
func testBuildsReadOnlyDashboardRows() {
    let model = DashboardPopoverModelBuilder().makeModel(
        state: stateWithUpdateApprovalAndError(),
        approvalStatuses: approvalStatuses()
    )

    XCTAssertEqual(model.updateCount, 1)
    XCTAssertEqual(model.approvalCount, 1)
    XCTAssertEqual(model.errorCount, 1)
    XCTAssertEqual(model.updates.first?.detail, "1.0 -> 1.1")
    XCTAssertEqual(model.approvals.first?.stateLabel, "Needs approval")
    XCTAssertEqual(model.errors.first?.stateLabel, "Error")
}
```

- [ ] **Step 2: Verify RED**

Run: `rtk test swift test --filter DashboardPopoverModelTests`

Expected: compilation fails because `DashboardPopoverModelBuilder` does not exist.

- [ ] **Step 3: Implement the minimal model**

Use this public boundary:

```swift
public struct DashboardPopoverRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let stateLabel: String
}

public struct DashboardPopoverModel: Equatable, Sendable {
    public let title: String
    public let trackedItemCount: Int
    public let updateCount: Int
    public let approvalCount: Int
    public let errorCount: Int
    public let lastChecked: Date?
    public let activeActionTitle: String?
    public let lastActionNotice: String?
    public let errorMessage: String?
    public let updates: [DashboardPopoverRow]
    public let approvals: [DashboardPopoverRow]
    public let errors: [DashboardPopoverRow]
}
```

The builder must call `SecretRedactor.redact` for errors, approval command text, active action, and notices. Do not include mutation actions.

- [ ] **Step 4: Verify GREEN**

Run: `rtk test swift test --filter DashboardPopoverModelTests`

Expected: all model tests pass.

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/UpdateBarMenuBar/DashboardPopoverModel.swift Tests/UpdateBarMenuBarTests/DashboardPopoverModelTests.swift
rtk git commit -m "Add read-only dashboard popover model"
```

### Task 2: Build The Compact Dashboard Surface

**Files:**
- Create: `Sources/UpdateBarMenuBarApp/DashboardPopoverView.swift`
- Create: `Sources/UpdateBarMenuBarApp/DashboardPopoverController.swift`

- [ ] **Step 1: Add source-contract RED tests**

Extend `SourceHygieneTests` to require `DashboardPopoverView`, `DashboardPopoverController`, a native segmented picker, a shared 340-point width, `.popover` material, an icon-only full-dashboard control, and no mutation callbacks or command grid.

- [ ] **Step 2: Verify RED**

Run: `rtk test swift test --filter SourceHygieneTests`

Expected: assertions fail because the dashboard popover files do not exist.

- [ ] **Step 3: Implement the SwiftUI view**

Create `DashboardPopoverTab` with `Overview`, `Updates`, and `Approvals`. Use `Picker("Section", selection:)` with `.segmented`, borderless read-only rows, `ScrollView`, system fonts, and stable dimensions:

```swift
enum DashboardPopoverLayout {
    static let size = CGSize(width: 340, height: 420)
}
```

The header must show UpdateBar, tracked count, health state, last checked time, and this icon-only command:

```swift
Button(action: onOpenFullDashboard) {
    Image(systemName: "arrow.up.right.square")
}
.buttonStyle(.borderless)
.help("Open Full Dashboard")
.accessibilityLabel("Open Full Dashboard")
```

Rows must not be buttons. Do not add Refresh, Update, Approve, Settings, or Quit controls.

- [ ] **Step 4: Implement the controller**

Own one transient `NSPopover`, reuse one `NSHostingView`, and host it inside `NSVisualEffectView`:

```swift
popover.behavior = .transient
effectView.material = .popover
effectView.blendingMode = .behindWindow
effectView.state = .followsWindowActiveState
```

Expose `show(relativeTo:model:onOpenFullDashboard:)`, `update(model:onOpenFullDashboard:)`, `close()`, and `isShown`.

- [ ] **Step 5: Build and verify GREEN**

Run:

```bash
rtk test swift test --filter SourceHygieneTests
rtk err swift build --target UpdateBarMenuBarApp
```

Expected: tests and app build pass.

### Task 3: Route Dashboard Without Replacing NSMenu

**Files:**
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`

- [ ] **Step 1: Add failing integration contracts**

Assert `applicationDidFinishLaunching` and `rebuildMenu` still assign `statusItem.menu`, the status button has no custom target/action, `.overview` calls `showDashboardPopover`, and only the Dashboard path invokes the popover controller.

- [ ] **Step 2: Verify RED**

Run: `rtk test swift test --filter SourceHygieneTests`

Expected: Dashboard routing assertions fail.

- [ ] **Step 3: Integrate the controller**

Add `dashboardPopoverModelBuilder`, `dashboardPopoverController`, and `lastDashboardError`. Replace the `.overview` selector body with `showDashboardPopover()`.

`showDashboardPopover()` must dispatch to the next main-loop turn, retrieve `statusItem.button`, and show the popover. If the button is unavailable, call the existing `showOverview()` full-window path.

The full-dashboard callback closes the popover and calls `showOverview()`. Successful refresh clears `lastDashboardError`; `showError` records a redacted error and updates a visible popover without changing the native recovery menu. `rebuildMenu` updates a visible popover after assigning the native menu.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
rtk test swift test --filter UpdateBarMenuBarTests
rtk err swift build --target UpdateBarMenuBarApp
```

Expected: focused tests and app build pass.

### Task 4: Documentation And Final Verification

**Files:**
- Modify: `docs/menu-bar.md`
- Modify: `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift`

- [ ] **Step 1: Update documentation**

Document that the status item opens a native menu, `Dashboard` opens the compact read-only popover, and the popover's full-dashboard control opens the separate chart window. State that commands remain in `NSMenu`.

- [ ] **Step 2: Run complete verification**

Run:

```bash
rtk test swift test
rtk err swift build -c release --product updatebar-menubar
rtk err xcrun swift-format lint --strict <changed-swift-files>
rtk git diff --check
rtk err Scripts/package-app.sh
rtk err Scripts/menubar-smoke-test.sh dist/UpdateBar.app
```

Expected: all commands exit 0.

- [ ] **Step 3: Manual QA**

Verify native menu presentation, Dashboard selection, popover anchoring, outside-click dismissal, tab persistence during refresh, full-dashboard opening, light/dark appearance, Reduce Transparency, keyboard focus, and VoiceOver labels.
