# Dashboard Selected Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add row-level and multi-select update actions to the Dashboard Items section while preserving Update All and the existing coordinated update engine.

**Architecture:** Extend the menu-bar service boundary with an explicit multi-ID update operation and route both row and batch Dashboard intents through `UpdateBarMenuBarApp.runAction`. Keep update eligibility and selection state in testable presentation models; keep AppKit responsible only for rendering and emitting intents.

**Tech Stack:** Swift 6, AppKit, Swift Package Manager, XCTest, existing UpdateBarCore update runner and menu-bar action coordinator.

---

## File Structure

- Modify `Sources/UpdateBarMenuBar/ManageItemsModel.swift`: expose update eligibility, disabled reasons, and deterministic selection state.
- Modify `Tests/UpdateBarMenuBarTests/ManageItemsModelTests.swift`: cover every eligibility state and selection behavior.
- Modify `Sources/UpdateBarMenuBar/MenuBarService.swift`: add the multi-ID service contract and Core implementation.
- Modify `Sources/UpdateBarMenuBar/UpdateBarCLIClient.swift`: pass multiple explicit IDs to subprocess mode.
- Modify `Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift`: prove explicit IDs use one bounded update operation.
- Modify `Tests/UpdateBarMenuBarTests/UpdateBarCLIClientTests.swift`: prove CLI argument ordering for multiple IDs.
- Modify `Tests/UpdateBarMenuBarTests/HistoryLogPresentationTests.swift`: update the test service conformance.
- Modify `Tests/UpdateBarMenuBarTests/ScanViewControllerTests.swift`: update the test service conformance.
- Modify `Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift`: render selection and row actions and emit update intents.
- Modify `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`: forward update intents and global busy state.
- Modify `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`: run explicit-ID updates through the existing action coordinator.
- Modify `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`: lock down AppKit wiring, accessibility, and separation of responsibilities.
- Modify `docs/menu-bar.md`: document Dashboard row and batch updates.

### Task 1: Model update eligibility and selection

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/ManageItemsModelTests.swift`
- Modify: `Sources/UpdateBarMenuBar/ManageItemsModel.swift`

- [ ] **Step 1: Write failing eligibility tests**

Add table-driven assertions showing `.outdated` is eligible and the other statuses expose stable reasons:

```swift
func testUpdateAvailabilityUsesResolvedStatus() throws {
    let cases: [(ItemStatus, Bool, String?)] = [
        (.outdated, true, nil),
        (.ok, false, "Up to date"),
        (.disabled, false, "Disabled"),
        (.untrusted, false, "Needs approval"),
        (.pinned, false, "Pinned"),
        (.checking, false, "Checking"),
        (.differs, false, "Version differs"),
        (.error, false, "Error"),
    ]

    for (status, expectedEligibility, expectedReason) in cases {
        let rows = ManageItemsModel().rows(from: [
            item(id: status.rawValue, name: status.rawValue, category: "cli", status: status)
        ])
        guard case .item(let row)? = rows.last else { return XCTFail("missing item row") }
        XCTAssertEqual(row.isUpdateEligible, expectedEligibility, status.rawValue)
        XCTAssertEqual(row.updateDisabledReason, expectedReason, status.rawValue)
    }
}
```

- [ ] **Step 2: Write failing selection tests**

```swift
func testSelectionAcceptsOnlyEligibleIDsAndReturnsSortedIDs() {
    var selection = ManageItemsSelectionModel()
    selection.toggle(id: "z", isEligible: true)
    selection.toggle(id: "blocked", isEligible: false)
    selection.toggle(id: "a", isEligible: true)

    XCTAssertEqual(selection.selectedIDs, ["a", "z"])
    XCTAssertTrue(selection.contains("z"))
    XCTAssertFalse(selection.contains("blocked"))

    selection.toggle(id: "z", isEligible: true)
    XCTAssertEqual(selection.selectedIDs, ["a"])
    selection.clear()
    XCTAssertTrue(selection.selectedIDs.isEmpty)
}
```

- [ ] **Step 3: Run focused tests and verify RED**

Run: `rtk test swift test --filter ManageItemsModelTests`

Expected: compilation fails because `isUpdateEligible`, `updateDisabledReason`, and `ManageItemsSelectionModel` do not exist.

- [ ] **Step 4: Implement the minimal presentation state**

Add these fields and model behavior:

```swift
public struct ManageItemRow: Equatable, Sendable {
    // existing fields
    public var updateDisabledReason: String?

    public var isUpdateEligible: Bool { updateDisabledReason == nil }
}

public struct ManageItemsSelectionModel: Equatable, Sendable {
    private var storage: Set<String> = []
    public var selectedIDs: [String] { storage.sorted() }
    public func contains(_ id: String) -> Bool { storage.contains(id) }

    public mutating func toggle(id: String, isEligible: Bool) {
        guard isEligible else { return }
        if !storage.insert(id).inserted { storage.remove(id) }
    }

    public mutating func clear() { storage.removeAll() }
}
```

Map resolved statuses to reasons in `ManageItemsModel`:

```swift
private static func updateDisabledReason(for item: StatusItem) -> String? {
    switch item.status {
    case .outdated: return nil
    case .ok: return "Up to date"
    case .disabled: return "Disabled"
    case .untrusted: return "Needs approval"
    case .pinned: return "Pinned"
    case .checking: return "Checking"
    case .differs: return "Version differs"
    case .error: return "Error"
    }
}
```

Pass `updateDisabledReason` from `row(from:)` and update existing expected rows.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run: `rtk test swift test --filter ManageItemsModelTests`

Expected: all Manage Items model tests pass.

- [ ] **Step 6: Commit**

```bash
rtk git add Sources/UpdateBarMenuBar/ManageItemsModel.swift Tests/UpdateBarMenuBarTests/ManageItemsModelTests.swift
rtk git commit -m "feat: model dashboard item update selection"
```

### Task 2: Add the explicit multi-ID service operation

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift`
- Modify: `Tests/UpdateBarMenuBarTests/UpdateBarCLIClientTests.swift`
- Modify: `Sources/UpdateBarMenuBar/MenuBarService.swift`
- Modify: `Sources/UpdateBarMenuBar/UpdateBarCLIClient.swift`
- Modify: `Tests/UpdateBarMenuBarTests/HistoryLogPresentationTests.swift`
- Modify: `Tests/UpdateBarMenuBarTests/ScanViewControllerTests.swift`

- [ ] **Step 1: Write a failing Core multi-ID test**

Create two trusted outdated recipes and record progress:

```swift
func testUpdateSelectedForwardsOnlyExplicitIDs() throws {
    // Save outdated recipes "alpha", "beta", and "ignored" with command results.
    let recorder = ProgressIDRecorder()

    try service.update(
        ids: ["beta", "alpha"],
        cancellationToken: nil,
        onEvent: { recorder.record($0) },
        stopSignal: nil
    )

    XCTAssertEqual(Set(recorder.startedIDs), Set(["alpha", "beta"]))
    XCTAssertFalse(recorder.startedIDs.contains("ignored"))
    XCTAssertEqual(Set(recorder.finishedIDs), Set(["alpha", "beta"]))
}
```

- [ ] **Step 2: Write a failing CLI argument test**

```swift
func testUpdateSelectedPassesEveryExplicitID() throws {
    let runner = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "[]", stderr: ""))
    let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

    try client.update(ids: ["alpha", "beta"])

    XCTAssertEqual(
        runner.calls,
        [CommandCall(
            executablePath: "/tmp/updatebar",
            arguments: ["update", "alpha", "beta", "--yes", "--json"]
        )]
    )
}
```

- [ ] **Step 3: Run focused tests and verify RED**

Run: `rtk test swift test --filter 'CoreMenuBarServiceTests|UpdateBarCLIClientTests'`

Expected: compilation fails because `update(ids:)` is missing.

- [ ] **Step 4: Extend the service protocol and implementations**

Make the multi-ID operation the required primitive:

```swift
func update(
    ids: [String],
    cancellationToken: CancellationToken?,
    onEvent: UpdateProgressHandler?,
    stopSignal: UpdateStopSignal?
) throws
```

Keep source compatibility through protocol conveniences:

```swift
public func update(id: String) throws {
    try update(ids: [id], cancellationToken: nil, onEvent: nil, stopSignal: nil)
}

public func update(
    id: String,
    cancellationToken: CancellationToken?,
    onEvent: UpdateProgressHandler?,
    stopSignal: UpdateStopSignal?
) throws {
    try update(ids: [id], cancellationToken: cancellationToken, onEvent: onEvent, stopSignal: stopSignal)
}

public func update(ids: [String]) throws {
    try update(ids: ids, cancellationToken: nil, onEvent: nil, stopSignal: nil)
}
```

Core implementation:

```swift
_ = try updateRunner(cancellationToken: cancellationToken).update(
    ids: ids,
    all: false,
    assumeYes: true,
    onEvent: onEvent,
    stopSignal: stopSignal
)
```

CLI implementation:

```swift
arguments: ["update"] + ids + ["--yes", "--json"]
```

Update the two test-only service conformers to implement the new `ids` signature instead of the old required `id` signature.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run: `rtk test swift test --filter 'CoreMenuBarServiceTests|UpdateBarCLIClientTests|HistoryLogPresentationTests|ScanViewControllerTests'`

Expected: selected-ID, CLI adapter, and test-conformance tests pass.

- [ ] **Step 6: Commit**

```bash
rtk git add Sources/UpdateBarMenuBar/MenuBarService.swift Sources/UpdateBarMenuBar/UpdateBarCLIClient.swift Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift Tests/UpdateBarMenuBarTests/UpdateBarCLIClientTests.swift Tests/UpdateBarMenuBarTests/HistoryLogPresentationTests.swift Tests/UpdateBarMenuBarTests/ScanViewControllerTests.swift
rtk git commit -m "feat: support explicit multi-item updates"
```

### Task 3: Add hybrid update controls to Items

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`
- Modify: `Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift`

- [ ] **Step 1: Write failing AppKit contract assertions**

Extend the existing Dashboard source contract:

```swift
XCTAssertTrue(manageItemsSource.contains("var onUpdateItems: ([String]) -> Void"))
XCTAssertTrue(manageItemsSource.contains("NSButton(title: \"Update Selected (0)\""))
XCTAssertTrue(manageItemsSource.contains("@objc private func toggleSelection("))
XCTAssertTrue(manageItemsSource.contains("@objc private func updateRow("))
XCTAssertTrue(manageItemsSource.contains("@objc private func updateSelectedItems("))
XCTAssertTrue(manageItemsSource.contains("setAccessibilityLabel"))
XCTAssertTrue(manageItemsSource.contains("setAccessibilityHelp"))
XCTAssertFalse(manageItemsSource.contains("service.update("))
```

- [ ] **Step 2: Run the source contract and verify RED**

Run: `rtk test swift test --filter SourceHygieneTests/testDashboardUsesOneSidebarWindowWithThreeEmbeddedSections`

Expected: failures for missing selection and update controls.

- [ ] **Step 3: Render selection and action columns**

In `ManageItemsViewController`, add:

```swift
var onUpdateItems: ([String]) -> Void = { _ in }
private var selectionModel = ManageItemsSelectionModel()
private var isActionBusy = false
private let updateSelectedButton = NSButton(
    title: "Update Selected (0)",
    target: nil,
    action: nil
)
```

Add `select` and `action` columns around the existing columns. Render selection checkboxes and row buttons with the row index in `tag`. An unavailable row disables both controls and assigns `updateDisabledReason` to `toolTip` and accessibility help. Eligible controls use `Select/Deselect <redacted name>` and `Update <redacted name>` labels.

Implement the three actions:

```swift
@objc private func toggleSelection(_ sender: NSButton) {
    guard rows.indices.contains(sender.tag), case .item(let item) = rows[sender.tag] else {
        return
    }
    selectionModel.toggle(id: item.id, isEligible: item.isUpdateEligible)
    updateControls()
}

@objc private func updateRow(_ sender: NSButton) {
    guard rows.indices.contains(sender.tag),
        case .item(let item) = rows[sender.tag], item.isUpdateEligible
    else { return }
    onUpdateItems([item.id])
}

@objc private func updateSelectedItems() {
    let ids = selectionModel.selectedIDs
    guard !ids.isEmpty else { return }
    onUpdateItems(ids)
}
```

Use explicit bounds checks rather than adding a collection extension. Clear selection at the beginning of `apply(items:)`. Add `setActionBusy(_:)` and include `isActionBusy` in every existing control's enabled state.

- [ ] **Step 4: Run focused tests and build the macOS target**

Run: `rtk test swift test --filter 'ManageItemsModelTests|SourceHygieneTests'`

Run: `rtk test swift build --target UpdateBarMenuBarApp`

Expected: tests pass and the AppKit target compiles.

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift
rtk git commit -m "feat: add dashboard item update controls"
```

### Task 4: Route Dashboard updates through the action coordinator

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`
- Modify: `Tests/UpdateBarMenuBarTests/HistoryLogPresentationTests.swift`
- Modify: `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`

- [ ] **Step 1: Write failing wiring contracts**

Assert the Dashboard forwards intents and receives busy state:

```swift
XCTAssertTrue(dashboardSource.contains("onUpdateItems: @escaping ([String]) -> Void"))
XCTAssertTrue(dashboardSource.contains("manageItemsViewController.onUpdateItems = onUpdateItems"))
XCTAssertTrue(dashboardSource.contains("func applyActionState(isBusy: Bool)"))
XCTAssertTrue(appSource.contains("onUpdateItems: { [weak self] ids in"))
XCTAssertTrue(appSource.contains("self?.update(ids: ids)"))
XCTAssertTrue(appSource.contains("dashboardPanelController?.applyActionState("))
```

Update `HistoryLogPresentationTests` construction with `onUpdateItems: { _ in }` so the new required closure is explicit.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `rtk test swift test --filter 'SourceHygieneTests|HistoryLogPresentationTests'`

Expected: source contracts fail because update intent and busy-state wiring are absent.

- [ ] **Step 3: Forward intents through DashboardPanelController**

Add `onUpdateItems` to its initializer and wire it once:

```swift
manageItemsViewController.onUpdateItems = onUpdateItems
```

Expose only the busy-state rendering entry point:

```swift
func applyActionState(isBusy: Bool) {
    manageItemsViewController.setActionBusy(isBusy)
}
```

- [ ] **Step 4: Add the top-level coordinated multi-ID action**

Refactor the existing single-ID helper:

```swift
private func update(id: String) {
    update(ids: [id])
}

private func update(ids: [String]) {
    guard !ids.isEmpty else { return }
    let title = ids.count == 1 ? "Updating \(ids[0])" : "Updating \(ids.count) selected items"
    runAction(title) { [service] action in
        try service?.update(
            ids: ids,
            cancellationToken: action.token,
            onEvent: self.progressHandler(for: action),
            stopSignal: action.stopSignal
        )
    }
}
```

Pass `onUpdateItems` when creating the Dashboard. Immediately apply `actionCoordinator.activeAction != nil` when opening the window, and in `rebuildMenu()` propagate the same state after reading `activeAction`.

- [ ] **Step 5: Run focused tests and build**

Run: `rtk test swift test --filter 'SourceHygieneTests|HistoryLogPresentationTests|MenuBarActionCoordinatorTests'`

Run: `rtk test swift build --target UpdateBarMenuBarApp`

Expected: wiring tests pass and the app compiles.

- [ ] **Step 6: Commit**

```bash
rtk git add Sources/UpdateBarMenuBarApp/DashboardPanelController.swift Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift Tests/UpdateBarMenuBarTests/HistoryLogPresentationTests.swift
rtk git commit -m "feat: coordinate dashboard selected updates"
```

### Task 5: Document and verify the finished behavior

**Files:**
- Modify: `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift`
- Modify: `docs/menu-bar.md`

- [ ] **Step 1: Write a failing documentation snapshot assertion**

Extend the existing menu-bar documentation test:

```swift
XCTAssertTrue(docs.contains("Update Selected"))
XCTAssertTrue(docs.contains("row-level Update"))
XCTAssertTrue(docs.contains("only outdated items are selectable"))
```

- [ ] **Step 2: Run the documentation test and verify RED**

Run: `rtk test swift test --filter DocumentationSnapshotTests/testMenuBarDocsDescribeCurrentNativeMenuAndUnifiedDashboardWindow`

Expected: the new copy assertions fail.

- [ ] **Step 3: Update Dashboard documentation**

Replace the Items paragraph with explicit behavior:

```markdown
Items lists every registered item grouped by category with a separate enable/disable checkbox. Eligible outdated rows also provide a row-level Update action. Users can select one or more eligible rows and run Update Selected; only outdated items are selectable. Current, disabled, pinned, checking, errored, and approval-blocked rows explain why updating is unavailable. Dashboard updates share the menu bar's global action state, progress, bounded parallelism, and Stop After Current behavior.
```

- [ ] **Step 4: Run documentation and full verification**

Run: `rtk test swift test --filter DocumentationSnapshotTests/testMenuBarDocsDescribeCurrentNativeMenuAndUnifiedDashboardWindow`

Run: `rtk test swift test`

Run: `rtk test bash Scripts/app-icon-test.sh`

Run: `rtk git diff --check`

Expected: all commands exit 0.

- [ ] **Step 5: Package and manually exercise the Dashboard**

Run: `rtk test bash Scripts/package-app.sh`

Launch the packaged app with an isolated `UPDATEBAR_HOME` containing at least two eligible outdated items and one ineligible item. Verify in the Items section:

- row Update starts exactly one item;
- selecting two eligible rows enables `Update Selected (2)` and starts both;
- ineligible rows cannot be selected and explain why;
- controls lock while the action runs;
- selection clears and status reloads after completion;
- menu-bar progress and Stop After Current remain available.

Expected: every scenario matches the approved design with no console errors.

- [ ] **Step 6: Commit**

```bash
rtk git add docs/menu-bar.md Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift
rtk git commit -m "docs: describe dashboard selected updates"
```

- [ ] **Step 7: Final branch audit**

Run: `rtk git status --short --branch`

Run: `rtk git log --oneline --decorate -8`

Expected: the feature branch is clean and contains the five focused implementation commits after the plan commit.
