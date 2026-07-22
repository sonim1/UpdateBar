# Dashboard Sidebar And Scan Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Dashboard's top tabs and standalone Scan panel with one left-sidebar Dashboard whose scan checkboxes immediately register, disable, or re-enable tools while preserving trust and recipe data.

**Architecture:** Keep all durable mutations behind the existing `MenuBarServicing` boundary. Add pure scan-row and mutation-gate types to `UpdateBarMenuBar`, convert Scan into a reusable AppKit child view controller, and let `DashboardPanelController` compose Overview, Items, and Scan inside one `NSSplitViewController`. Compact UI copy remains presentation-only; CLI JSON/stdout contracts and `UpdateBarCore` trust rules do not change.

**Tech Stack:** Swift 6, SwiftPM, AppKit, SwiftUI, Swift Charts, XCTest, OpenSpec.

**Design reference:** `docs/superpowers/specs/2026-07-21-dashboard-sidebar-scan-design.md`

**Repository rule:** Commit steps are intentionally omitted because `CLAUDE.md` forbids commits unless Kendrick explicitly requests them. If authorization is given later, commit each completed task separately with the task-specific files only.

---

## File Map

### Create

- `openspec/changes/dashboard-sidebar-scan/.openspec.yaml` — OpenSpec change metadata.
- `openspec/changes/dashboard-sidebar-scan/proposal.md` — user-visible motivation, compatibility, and scope.
- `openspec/changes/dashboard-sidebar-scan/design.md` — presentation and trust-boundary decisions.
- `openspec/changes/dashboard-sidebar-scan/tasks.md` — checkable implementation and verification list.
- `openspec/changes/dashboard-sidebar-scan/specs/macos-menubar/spec.md` — delta requirements for the Dashboard and Scan behavior.
- `Sources/UpdateBarMenuBar/ScanMutationGate.swift` — pure per-row pending-mutation state.
- `Tests/UpdateBarMenuBarTests/ScanMutationGateTests.swift` — mutation concurrency and rollback tests.
- `Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift` — native sidebar selection UI.
- `Sources/UpdateBarMenuBarApp/DashboardOverviewView.swift` — compact Overview SwiftUI and accessible chart presentation moved out of the window controller.
- `Sources/UpdateBarMenuBarApp/ScanViewController.swift` — embedded manual Scan UI with immediate row toggles.

### Modify

- `Sources/UpdateBarMenuBar/ScanListModel.swift` — replace batch-selection flags with stable tracking states.
- `Tests/UpdateBarMenuBarTests/ScanListModelTests.swift` — cover untracked, enabled, disabled, and unavailable mappings.
- `Sources/UpdateBarMenuBar/ManageItemsMutationGate.swift` — expose the pending item ID for row-local progress UI.
- `Tests/UpdateBarMenuBarTests/ManageItemsModelTests.swift` — verify pending-item identity and cancellation.
- `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift` — own the split view, three reusable sections, and shared refresh.
- `Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift` — icon-only refresh and row-local progress/error feedback without persistent status copy.
- `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift` — route all three menu actions to the single Dashboard and remove standalone Scan ownership.
- `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift` — replace tabbed-window contracts with sidebar, unified Scan, compact-copy, and accessibility contracts.
- `docs/menu-bar.md` — describe the sidebar and immediate tracking toggles.
- `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift` — lock the new documentation wording.

### Delete

- `Sources/UpdateBarMenuBarApp/ScanPanelController.swift` — replaced by reusable `ScanViewController`.

No `UpdateBarCore`, CLI payload, package dependency, release, or script file changes are required.

---

### Task 1: Record The Behavior Change In OpenSpec

**Files:**
- Create: `openspec/changes/dashboard-sidebar-scan/.openspec.yaml`
- Create: `openspec/changes/dashboard-sidebar-scan/proposal.md`
- Create: `openspec/changes/dashboard-sidebar-scan/design.md`
- Create: `openspec/changes/dashboard-sidebar-scan/tasks.md`
- Create: `openspec/changes/dashboard-sidebar-scan/specs/macos-menubar/spec.md`

- [ ] **Step 1: Create the change metadata**

```yaml
schema: spec-driven
created: 2026-07-21
```

- [ ] **Step 2: Write the proposal with explicit compatibility boundaries**

```markdown
## Why

Dashboard navigation is split between a top tab control and a separate Scan
panel. The duplicated window behavior makes the macOS app feel fragmented, and
the Scan panel's batch `Add Selected` action duplicates the meaning of its
checkboxes.

## What Changes

- Replace the Dashboard's top tabs with a native left sidebar for Overview,
  Items, and Scan & Add.
- Route all three native menu actions to the same reusable Dashboard window.
- Keep Scan manual, remove `Add Selected`, and make each checkbox immediately
  register, disable, or re-enable its candidate.
- Reduce persistent helper text across Dashboard sections while preserving
  tooltips and accessibility labels.

## Compatibility

- No CLI stdout, JSON, JSONL, exit-code, manifest-schema, or history-schema
  changes.
- New registrations remain untrusted.
- Unchecking never removes a recipe, approval, state entry, or history event.
- Core and CLI menu-bar adapters continue using existing registration and
  enable/disable operations.

## Capabilities

### Modified Capabilities

- `macos-menubar`: unify Dashboard navigation, embed Scan & Add, define immediate
  tracking toggles, and preserve compact accessible help.

## Impact

- `UpdateBarMenuBar` scan presentation models and tests.
- `UpdateBarMenuBarApp` Dashboard, Items, Scan, and app routing.
- macOS menu-bar documentation and source-contract tests.
```

- [ ] **Step 3: Write the macOS Menu Bar delta specification**

```markdown
## ADDED Requirements

### Requirement: Dashboard uses one sidebar window
The macOS Menu Bar app SHALL present Overview, Items, and Scan & Add in one
reusable Dashboard window with native left-sidebar navigation.

#### Scenario: User opens a Dashboard section
- **WHEN** the user selects Dashboard, Manage Items, or Scan & Add from the
  native menu
- **THEN** the app SHALL open the same Dashboard window with the matching
  sidebar section selected

### Requirement: Scan checkboxes control tracking immediately
The Scan & Add section SHALL scan only after explicit user action and SHALL use
each row checkbox as the immediate tracking control.

#### Scenario: User checks an untracked candidate
- **WHEN** the candidate contains a complete recipe and the user checks it
- **THEN** the app SHALL register it enabled and untrusted without approving any
  command

#### Scenario: User unchecks a tracked candidate
- **WHEN** the user unchecks an enabled candidate
- **THEN** the app SHALL disable it without deleting its recipe, approvals,
  state, or history

#### Scenario: User rechecks a disabled candidate
- **WHEN** the user checks a disabled registered candidate
- **THEN** the app SHALL enable the existing recipe without replacing it

#### Scenario: A row mutation fails
- **WHEN** registration, disable, or enable fails
- **THEN** the app SHALL restore the previous checkbox state and expose a
  redacted row-local failure

### Requirement: Dashboard helper copy is compact and accessible
The Dashboard SHALL keep supplementary status explanations out of the permanent
layout while preserving their meaning in native tooltips and accessibility
labels.

#### Scenario: User inspects compact controls
- **WHEN** a metric, count badge, info icon, or icon-only refresh control is
  focused or hovered
- **THEN** the app SHALL expose its unabridged meaning through an accessibility
  label or tooltip
```

- [ ] **Step 4: Write `design.md` and `tasks.md` from the approved design**

Use this exact `design.md` content:

```markdown
## Context

The current Dashboard owns Overview and Items in an `NSTabViewController`, while
Scan & Add owns a second `NSPanel`. Scan checkboxes are temporary batch selection
and require `Add Selected` before they affect the registry.

## Goals / Non-Goals

Goals are one Dashboard window, native sidebar navigation, explicit manual
scanning, immediate row tracking controls, compact visible copy, and preserved
trust semantics. Non-goals are registry deletion, automatic scanning, automatic
approval, CLI contract changes, and redesign of Config, TUI, or the native menu.

## Decisions

### One native split window

`DashboardPanelController` owns an `NSSplitViewController`. A fixed sidebar maps
the `DashboardSection` cases Overview, Items, and Scan to reusable child view
controllers. Native menu routes select a section in the same window.

### Scan remains explicit

Selecting Scan & Add never starts discovery. The visible `Scan` button calls the
existing `MenuBarServicing.scan` operation and joins candidates with status by
ID.

### Checkboxes are tracking controls

Checking an untracked full candidate calls `registerScannedCandidates` for that
one ID. Unchecking an enabled candidate calls `setEnabled(false)`. Checking a
disabled candidate calls `setEnabled(true)`. No Scan interaction calls `remove`.

### Preserve the trust boundary

Registration continues through `InitService`, so imported commands remain
untrusted. Disabling preserves recipe fields, approvals, state, and history.

### Compact copy remains accessible

Overview metric titles, Scan count descriptions, info help, and the Items
refresh label move from persistent copy to native tooltips and accessibility
labels. Essential table headers, state labels, errors, and recovery remain
visible or available through native error presentation.

## Risks / Trade-offs

- Immediate mutations can race, so pending work is keyed by candidate ID and a
  duplicate mutation for one ID is blocked.
- Hidden explanations can hurt discovery, so every compact control has both a
  tooltip and an accessibility label.
- A sidebar consumes horizontal space, so the window and minimum width increase
  while the content minimum remains usable.

## Rollback

Revert the sidebar composition and restore the standalone Scan panel without
changing manifest, state, trust, history, or CLI formats.
```

Use this exact checklist in `tasks.md`:

```markdown
## 1. Scan state model
- [ ] 1.1 Model untracked, enabled, disabled, and unavailable scan rows.
- [ ] 1.2 Add per-row mutation gating and rollback tests.

## 2. Unified Dashboard
- [ ] 2.1 Replace top tabs with native sidebar navigation.
- [ ] 2.2 Embed Scan & Add and remove the standalone Scan panel.
- [ ] 2.3 Route all three native menu actions to one window.

## 3. Compact presentation
- [ ] 3.1 Reduce persistent helper copy in Overview.
- [ ] 3.2 Reduce persistent helper copy in Items.
- [ ] 3.3 Add compact Scan counts, tooltips, and accessibility labels.

## 4. Verification
- [ ] 4.1 Update source and documentation contracts.
- [ ] 4.2 Run targeted tests and `Scripts/quality-gate.sh`.
```

- [ ] **Step 5: Validate the OpenSpec change**

Run: `rtk openspec validate dashboard-sidebar-scan --strict`

Expected: the change validates with no missing sections or scenario errors.

---

### Task 2: Replace Batch Selection With Pure Tracking State

**Files:**
- Modify: `Sources/UpdateBarMenuBar/ScanListModel.swift:3-35`
- Modify: `Tests/UpdateBarMenuBarTests/ScanListModelTests.swift:5-68`
- Create: `Sources/UpdateBarMenuBar/ScanMutationGate.swift`
- Create: `Tests/UpdateBarMenuBarTests/ScanMutationGateTests.swift`

- [ ] **Step 1: Write failing scan-state mapping tests**

Replace assertions based on `isRegistered`, `isSelected`, and `isImportable`
with explicit state assertions:

```swift
func testMapsRegisteredStatusesBeforeCandidateCapability() throws {
    let report = try trackingReport()

    let rows = ScanListModel().rows(
        from: report,
        registeredStatuses: ["brew.jq": .disabled, "known.claude": .untrusted]
    )

    XCTAssertEqual(rows.map(\.trackingState), [.disabled, .enabled])
    XCTAssertEqual(rows.map(\.isChecked), [false, true])
    XCTAssertEqual(rows.map(\.canToggle), [true, true])
}

func testMapsNewCandidatesToUntrackedOrUnavailable() throws {
    let report = try trackingReport()

    let rows = ScanListModel().rows(from: report, registeredStatuses: [:])

    XCTAssertEqual(rows.map(\.trackingState), [.untracked, .unavailable("check-only")])
    XCTAssertEqual(rows.map(\.isChecked), [false, false])
    XCTAssertEqual(rows.map(\.canToggle), [true, false])
}

private func trackingReport() throws -> ScanReport {
    try decodeReport(
        """
        {"candidates":[
          {"id":"brew.jq","name":"jq","category":"shell-utility","detector":"brew",
           "capability":"full","confidence":"high","source_ref":"jq",
           "installed_version":"1.7.1",
           "recipe":{"category":"shell-utility","check":{"cmd":"brew list --versions jq"},
             "id":"brew.jq","latest":{"cmd":"brew info jq","strategy":"cmd"},
             "name":"jq","source":{"kind":"brew","ref":"jq"},
             "update":{"cmd":"brew upgrade jq"},
             "version_parse":{"regex":"([0-9]+\\.[0-9]+\\.[0-9]+)"},
             "version_scheme":"semver","enabled":true,
             "trust":{"level":"untrusted","approved_commands":{}}}},
          {"id":"known.claude","name":"claude","category":"ai-agent","detector":"known",
           "capability":"check-only","confidence":"medium","source_ref":"claude"}
        ],"errors":[]}
        """
    )
}
```

- [ ] **Step 2: Run the scan model tests and confirm the red state**

Run: `rtk test swift test --filter ScanListModelTests`

Expected: compilation fails because `trackingState`, `isChecked`, `canToggle`,
and the `registeredStatuses` parameter do not exist.

- [ ] **Step 3: Implement the minimal tracking-state model**

```swift
import Foundation
import UpdateBarCore

public enum ScanTrackingState: Equatable, Sendable {
    case untracked
    case enabled
    case disabled
    case unavailable(String)
}

public struct ScanListRow: Equatable {
    public var candidate: ScanCandidate
    public var trackingState: ScanTrackingState

    public init(candidate: ScanCandidate, trackingState: ScanTrackingState) {
        self.candidate = candidate
        self.trackingState = trackingState
    }

    public var isChecked: Bool { trackingState == .enabled }

    public var canToggle: Bool {
        if case .unavailable = trackingState { return false }
        return true
    }

    public var stateLabel: String {
        switch trackingState {
        case .untracked: return "new"
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .unavailable(let reason): return reason
        }
    }
}

public struct ScanListModel: Sendable {
    public init() {}

    public func rows(
        from report: ScanReport,
        registeredStatuses: [String: ItemStatus]
    ) -> [ScanListRow] {
        report.candidates.map { candidate in
            let state: ScanTrackingState
            if let status = registeredStatuses[candidate.id] {
                state = status == .disabled ? .disabled : .enabled
            } else if candidate.capability == .full, candidate.recipe != nil {
                state = .untracked
            } else {
                state = .unavailable(candidate.capability.rawValue)
            }
            return ScanListRow(candidate: candidate, trackingState: state)
        }
    }
}
```

- [ ] **Step 4: Run the scan model tests and confirm green**

Run: `rtk test swift test --filter ScanListModelTests`

Expected: all `ScanListModelTests` pass.

- [ ] **Step 5: Write failing per-ID mutation-gate tests**

```swift
import UpdateBarMenuBar
import XCTest

final class ScanMutationGateTests: XCTestCase {
    func testDifferentRowsCanMutateWhileDuplicateIDIsRejected() {
        var gate = ScanMutationGate()

        XCTAssertNotNil(gate.begin(id: "jq", previous: .untracked, target: .enabled))
        XCTAssertNotNil(gate.begin(id: "rg", previous: .enabled, target: .disabled))
        XCTAssertNil(gate.begin(id: "jq", previous: .untracked, target: .enabled))
        XCTAssertTrue(gate.hasPendingMutations)
        XCTAssertTrue(gate.isPending(id: "jq"))
        XCTAssertTrue(gate.isPending(id: "rg"))
    }

    func testFinishReturnsTheMutationNeededForSuccessOrRollback() {
        var gate = ScanMutationGate()
        let started = gate.begin(id: "jq", previous: .enabled, target: .disabled)

        XCTAssertEqual(gate.finish(id: "jq"), started)
        XCTAssertFalse(gate.hasPendingMutations)
        XCTAssertNil(gate.finish(id: "jq"))
    }
}
```

- [ ] **Step 6: Run the mutation tests and confirm the red state**

Run: `rtk test swift test --filter ScanMutationGateTests`

Expected: compilation fails because `ScanMutationGate` does not exist.

- [ ] **Step 7: Implement the per-ID mutation gate**

```swift
public struct ScanRowMutation: Equatable, Sendable {
    public var id: String
    public var previous: ScanTrackingState
    public var target: ScanTrackingState
}

public struct ScanMutationGate: Sendable {
    private var mutationsByID: [String: ScanRowMutation] = [:]

    public init() {}

    public var hasPendingMutations: Bool { !mutationsByID.isEmpty }

    public func isPending(id: String) -> Bool { mutationsByID[id] != nil }

    public mutating func begin(
        id: String,
        previous: ScanTrackingState,
        target: ScanTrackingState
    ) -> ScanRowMutation? {
        guard mutationsByID[id] == nil else { return nil }
        let mutation = ScanRowMutation(id: id, previous: previous, target: target)
        mutationsByID[id] = mutation
        return mutation
    }

    @discardableResult
    public mutating func finish(id: String) -> ScanRowMutation? {
        mutationsByID.removeValue(forKey: id)
    }
}
```

- [ ] **Step 8: Run both focused model suites**

Run: `rtk test swift test --filter 'Scan(ListModel|MutationGate)Tests'`

Expected: both suites pass.

---

### Task 3: Convert Scan Into An Embedded Immediate-Toggle View

**Files:**
- Create: `Sources/UpdateBarMenuBarApp/ScanViewController.swift`
- Delete: `Sources/UpdateBarMenuBarApp/ScanPanelController.swift`
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift:192-246`

- [ ] **Step 1: Write failing source contracts for the embedded Scan view**

Add this test before changing the UI source:

```swift
func testScanIsEmbeddedAndUsesImmediateTrackingToggles() throws {
    let path = "Sources/UpdateBarMenuBarApp/ScanViewController.swift"
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    XCTAssertFalse(
        FileManager.default.fileExists(
            atPath: "Sources/UpdateBarMenuBarApp/ScanPanelController.swift"
        )
    )

    let source = try String(contentsOfFile: path, encoding: .utf8)
    XCTAssertTrue(source.contains("final class ScanViewController: NSViewController"))
    XCTAssertTrue(source.contains(#"NSButton(title: "Scan""#))
    XCTAssertTrue(source.contains("registerScannedCandidates("))
    XCTAssertTrue(source.contains("setEnabled(id:"))
    XCTAssertTrue(source.contains("ScanMutationGate"))
    XCTAssertTrue(source.contains("scanButton.toolTip"))
    XCTAssertTrue(source.contains("infoButton.toolTip"))
    XCTAssertTrue(source.contains("setAccessibilityLabel"))
    XCTAssertFalse(source.contains("NSPanel("))
    XCTAssertFalse(source.contains("Add Selected"))
    XCTAssertFalse(source.contains("addSelected"))
}
```

- [ ] **Step 2: Run the source contract and confirm red**

Run: `rtk test swift test --filter SourceHygieneTests/testScanIsEmbeddedAndUsesImmediateTrackingToggles`

Expected: FAIL because `ScanViewController.swift` does not exist and the old
panel still exists.

- [ ] **Step 3: Create the reusable controller shell and compact controls**

Move the existing table construction into an `NSViewController`, remove the
window creation and batch action, and use these stored properties and callbacks.
Keep the existing sendability boundary as a one-candidate box so the background
closure does not capture non-`Sendable` scan model values:

```swift
private final class ScanCandidateBox: @unchecked Sendable {
    let value: ScanCandidate

    init(_ value: ScanCandidate) {
        self.value = value
    }
}

final class ScanViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate
{
    private let service: any MenuBarServicing
    private let onChanged: () -> Void
    private let listModel = ScanListModel()
    private var mutationGate = ScanMutationGate()
    private var scanGenerationGate = MenuBarRefreshGenerationGate()
    private var report: ScanReport?
    private var rows: [ScanListRow] = []
    private var errorsByID: [String: String] = [:]
    private var isScanning = false

    var onError: (Error) -> Void = { _ in }

    private let tableView = NSTableView()
    private let scanButton = NSButton(title: "Scan", target: nil, action: nil)
    private let discoveredBadge = NSTextField(labelWithString: "0")
    private let enabledBadge = NSTextField(labelWithString: "0")
    private let disabledBadge = NSTextField(labelWithString: "0")
    private let infoButton = NSButton(
        image: NSImage(
            systemSymbolName: "info.circle",
            accessibilityDescription: "Tracking behavior"
        ) ?? NSImage(),
        target: nil,
        action: nil
    )

    init(service: any MenuBarServicing, onChanged: @escaping () -> Void) {
        self.service = service
        self.onChanged = onChanged
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }
}
```

Set these native help and accessibility contracts while building the controls:

```swift
scanButton.toolTip = "Scan for installed tools"
scanButton.setAccessibilityLabel("Scan for installed tools")
infoButton.isBordered = false
infoButton.toolTip =
    "Checked tools are enabled. Unchecked registered tools are disabled, not deleted."
infoButton.setAccessibilityLabel("Tracking behavior help")
```

Each count badge must display only its integer and expose full text through both
`toolTip` and `setAccessibilityLabel`, for example `"8 tools discovered"`.

- [ ] **Step 4: Implement manual scanning and stable row rebuilding**

Use one status read per scan and never call `runScan()` from `viewDidLoad` or
section selection:

```swift
@objc private func runScan() {
    let generation = scanGenerationGate.begin()
    isScanning = true
    updateControls()
    DispatchQueue.global(qos: .userInitiated).async { [service] in
        do {
            let report = try service.scan(category: nil)
            let snapshot = try service.status(refresh: false)
            DispatchQueue.main.async {
                guard self.scanGenerationGate.isCurrent(generation) else { return }
                self.report = report
                self.applyRegisteredItems(snapshot.items)
                self.isScanning = false
                self.updateControls()
            }
        } catch {
            DispatchQueue.main.async {
                guard self.scanGenerationGate.isCurrent(generation) else { return }
                self.isScanning = false
                self.updateControls()
                self.onError(error)
            }
        }
    }
}

func applyRegisteredItems(_ items: [StatusItem]) {
    guard let report else { return }
    let statuses = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.status) })
    rows = listModel.rows(from: report, registeredStatuses: statuses)
    tableView.reloadData()
    updateCounts()
}
```

- [ ] **Step 5: Implement immediate register, disable, and enable mutations**

The checkbox handler must derive one target and never call `remove`:

```swift
@objc private func toggleCandidate(_ sender: NSButton) {
    guard rows.indices.contains(sender.tag) else { return }
    let row = rows[sender.tag]
    let target: ScanTrackingState
    switch row.trackingState {
    case .untracked, .disabled:
        target = .enabled
    case .enabled:
        target = .disabled
    case .unavailable:
        return
    }
    guard mutationGate.begin(
        id: row.candidate.id,
        previous: row.trackingState,
        target: target
    ) != nil else { return }

    let id = row.candidate.id
    let previous = row.trackingState
    let candidate = ScanCandidateBox(row.candidate)
    errorsByID[id] = nil
    tableView.reloadData()
    updateControls()
    DispatchQueue.global(qos: .userInitiated).async { [service] in
        do {
            switch previous {
            case .untracked:
                _ = try service.registerScannedCandidates(
                    [candidate.value],
                    selectedIDs: [id],
                    replace: false
                )
            case .enabled:
                try service.setEnabled(id: id, enabled: false)
            case .disabled:
                try service.setEnabled(id: id, enabled: true)
            case .unavailable:
                return
            }
            DispatchQueue.main.async {
                self.finishMutation(id: id, error: nil)
                self.onChanged()
            }
        } catch {
            DispatchQueue.main.async {
                self.finishMutation(id: id, error: error)
                self.onError(error)
            }
        }
    }
}
```

`finishMutation(id:error:)` must call `mutationGate.finish(id:)`, set the row to
the mutation target on success or the previous state on failure, store only a
redacted error, reload the affected row, update the count badges, and restore the
Scan button when no mutations remain. `updateControls()` uses
`scanButton.isEnabled = !isScanning && !mutationGate.hasPendingMutations`. The
row checkbox is disabled and replaced or accompanied by `NSProgressIndicator`
only while its ID is pending.

- [ ] **Step 6: Remove the old panel source and run focused tests**

Delete `Sources/UpdateBarMenuBarApp/ScanPanelController.swift` only after
`ScanViewController.swift` contains the table columns, checkbox cell,
redaction, error callback, and accessibility behavior.

Run: `rtk test swift test --filter 'Scan(ListModel|MutationGate)Tests|SourceHygieneTests/testScanIsEmbedded'`

Expected: all selected tests pass.

Run: `rtk swift build --product updatebar-menubar`

Expected: the embedded Scan controller compiles in the macOS app target.

---

### Task 4: Replace Dashboard Tabs With A Native Sidebar And Unify Routing

**Files:**
- Create: `Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift`
- Modify: `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift:212-337`
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift:18-20,185-224`
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift:209-323`

- [ ] **Step 1: Replace tab contracts with failing sidebar and routing contracts**

Replace `testDashboardUsesOneTabbedWindowWithEmbeddedItems` and update the
routing test with these assertions:

```swift
func testDashboardUsesOneSidebarWindowWithThreeSections() throws {
    let dashboard = try String(
        contentsOfFile: "Sources/UpdateBarMenuBarApp/DashboardPanelController.swift",
        encoding: .utf8
    )
    let sidebar = try String(
        contentsOfFile: "Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift",
        encoding: .utf8
    )
    let compact = dashboard.filter { !$0.isWhitespace }

    XCTAssertTrue(sidebar.contains("enum DashboardSection: Int, CaseIterable"))
    XCTAssertTrue(sidebar.contains("case overview"))
    XCTAssertTrue(sidebar.contains("case items"))
    XCTAssertTrue(sidebar.contains("case scan"))
    XCTAssertTrue(dashboard.contains("NSSplitViewController"))
    XCTAssertTrue(dashboard.contains("NSSplitViewItem(sidebarWithViewController:"))
    XCTAssertTrue(dashboard.contains("ManageItemsViewController"))
    XCTAssertTrue(dashboard.contains("ScanViewController"))
    XCTAssertTrue(compact.contains("funcshowWindowAndReload(selectingsection:DashboardSection)"))
    XCTAssertFalse(dashboard.contains("NSTabViewController"))
    XCTAssertFalse(dashboard.contains("DashboardTab"))
}

func testNativeMenuRoutesAllDashboardSectionsToOneWindow() throws {
    let source = try String(
        contentsOfFile: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift",
        encoding: .utf8
    )
    let compact = source.filter { !$0.isWhitespace }

    XCTAssertTrue(compact.contains("@objcprivatefuncshowOverview(){showDashboard(.overview)}"))
    XCTAssertTrue(compact.contains("@objcprivatefuncmanageItems(){showDashboard(.items)}"))
    XCTAssertTrue(compact.contains("@objcprivatefuncscanAndAdd(){showDashboard(.scan)}"))
    XCTAssertFalse(source.contains("scanPanelController"))
    XCTAssertFalse(source.contains("ScanPanelController"))
}
```

- [ ] **Step 2: Run the focused source tests and confirm red**

Run: `rtk test swift test --filter 'SourceHygieneTests/testDashboardUsesOneSidebar|SourceHygieneTests/testNativeMenuRoutesAll'`

Expected: FAIL because the Dashboard still uses `NSTabViewController`, has no
sidebar source, and owns a separate Scan panel.

- [ ] **Step 3: Implement the sidebar selection component**

Create `DashboardSection` and a native list-style table with these exact public
hooks:

```swift
enum DashboardSection: Int, CaseIterable {
    case overview
    case items
    case scan

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .items: return "Items"
        case .scan: return "Scan & Add"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "chart.bar"
        case .items: return "list.bullet"
        case .scan: return "magnifyingglass"
        }
    }
}

final class DashboardSidebarViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate
{
    var onSelectionChanged: (DashboardSection) -> Void = { _ in }
    private let tableView = NSTableView()

    func select(_ section: DashboardSection) {
        tableView.selectRowIndexes(IndexSet(integer: section.rawValue), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        DashboardSection.allCases.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let section = DashboardSection(rawValue: tableView.selectedRow) else { return }
        onSelectionChanged(section)
    }
}
```

In `loadView`, configure a headerless `NSTableView` inside an `NSScrollView`, use
`selectionHighlightStyle = .sourceList`, create SF Symbol plus text cells, set an
accessibility label for every row, and constrain the sidebar to 150–190 points.

- [ ] **Step 4: Compose the three reusable child controllers**

In `DashboardPanelController`, replace tab ownership with:

```swift
private let splitViewController = NSSplitViewController()
private let sidebarViewController = DashboardSidebarViewController()
private let contentViewController = NSViewController()
private let overviewViewController = NSViewController()
private let manageItemsViewController: ManageItemsViewController
private let scanViewController: ScanViewController
private var selectedSection: DashboardSection = .overview
private var visibleChildViewController: NSViewController?
```

Build the split view with `NSSplitViewItem(sidebarWithViewController:)` and a
normal content item. Implement section swapping without recreating children:

```swift
private func select(_ section: DashboardSection) {
    selectedSection = section
    sidebarViewController.select(section)
    let next: NSViewController
    switch section {
    case .overview: next = overviewViewController
    case .items: next = manageItemsViewController
    case .scan: next = scanViewController
    }
    guard next !== visibleChildViewController else { return }
    visibleChildViewController?.view.removeFromSuperview()
    visibleChildViewController?.removeFromParent()
    contentViewController.addChild(next)
    contentViewController.view.addSubview(next.view)
    next.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        next.view.leadingAnchor.constraint(equalTo: contentViewController.view.leadingAnchor),
        next.view.trailingAnchor.constraint(equalTo: contentViewController.view.trailingAnchor),
        next.view.topAnchor.constraint(equalTo: contentViewController.view.topAnchor),
        next.view.bottomAnchor.constraint(equalTo: contentViewController.view.bottomAnchor),
    ])
    visibleChildViewController = next
}
```

`showWindowAndReload(selecting:)` selects the requested section, shows the same
window, and calls the existing shared `reload()`. `reload()` continues to fetch
status and history once, then applies the snapshot to Overview, Items, and
`scanViewController.applyRegisteredItems(snapshot.items)`; that Scan method is a
no-op until a manual scan has produced a report. Initialize
`contentViewController.view` with an empty `NSView` before swapping children,
and widen the window to 840 points with a 760-point minimum so the content area
does not shrink below the current usable width after adding the sidebar.

- [ ] **Step 5: Route Scan through the Dashboard and remove panel ownership**

Delete the `scanPanelController` property and replace the existing method body:

```swift
@objc private func scanAndAdd() {
    showDashboard(.scan)
}

private func showDashboard(_ section: DashboardSection) {
    guard let service else {
        showError(MenuBarStartupError.serviceUnavailable)
        return
    }
    NSApp.setActivationPolicy(.regular)
    if dashboardPanelController == nil {
        dashboardPanelController = DashboardPanelController(
            service: service,
            onItemsChanged: { [weak self] in
                self?.refreshStatus(refresh: false)
            }
        )
    }
    dashboardPanelController?.showWindowAndReload(selecting: section)
}
```

Keep `showOverview` and `manageItems`, but pass `.overview` and `.items` through
the new `DashboardSection` type.

- [ ] **Step 6: Run sidebar, routing, refresh, and activation-policy tests**

Run: `rtk test swift test --filter SourceHygieneTests`

Expected: all source contracts pass, including one-window reuse, one shared
status read, stale reload rejection, and `.regular`/`.accessory` transitions.

Run: `rtk swift build --product updatebar-menubar`

Expected: the sidebar, section swapping, and unified routing compile.

---

### Task 5: Reduce Persistent Copy Across Overview And Items

**Files:**
- Create: `Sources/UpdateBarMenuBarApp/DashboardOverviewView.swift`
- Modify: `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift:1-210`
- Modify: `Sources/UpdateBarMenuBar/ManageItemsMutationGate.swift:1-32`
- Modify: `Tests/UpdateBarMenuBarTests/ManageItemsModelTests.swift:95-137`
- Modify: `Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift:13-195`
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`

- [ ] **Step 1: Write failing compact-copy and accessibility contracts**

```swift
func testDashboardSectionsUseCompactCopyWithAccessibleHelp() throws {
    let overview = try String(
        contentsOfFile: "Sources/UpdateBarMenuBarApp/DashboardOverviewView.swift",
        encoding: .utf8
    )
    let items = try String(
        contentsOfFile: "Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift",
        encoding: .utf8
    )

    XCTAssertTrue(overview.contains(#"Text("Overview")"#))
    XCTAssertTrue(overview.contains(".help("))
    XCTAssertTrue(overview.contains(".accessibilityLabel("))
    XCTAssertFalse(overview.contains(#"Text("UpdateBar")"#))
    XCTAssertFalse(overview.contains("Everything is up to date"))
    XCTAssertFalse(overview.contains("Text(title)"))

    XCTAssertTrue(items.contains(#"systemSymbolName: "arrow.clockwise""#))
    XCTAssertTrue(items.contains("refreshButton.toolTip"))
    XCTAssertTrue(items.contains("refreshButton.setAccessibilityLabel"))
    XCTAssertFalse(items.contains(#"NSButton(title: "Refresh""#))
    XCTAssertFalse(items.contains("statusLabel"))
    XCTAssertFalse(items.contains(#"labelWithString: "Ready""#))
}
```

- [ ] **Step 2: Run the compact-copy contract and confirm red**

Run: `rtk test swift test --filter SourceHygieneTests/testDashboardSectionsUseCompactCopyWithAccessibleHelp`

Expected: FAIL because Overview is still inside the panel controller with
visible metric labels and Items still has visible Refresh and status text.

- [ ] **Step 3: Move and compact the Overview view without changing its model**

Move `DashboardView` and `UpdatesChartDescriptor` into
`DashboardOverviewView.swift`, rename the view to `DashboardOverviewView`, and
preserve the existing `DashboardSummary` input and chart descriptor.

Use this tile body so visible content is icon plus value only:

```swift
private func tile(
    title: String,
    value: String,
    helpValue: String? = nil,
    systemImage: String
) -> some View {
    HStack(spacing: 8) {
        Image(systemName: systemImage)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        Text(value)
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .background(
        .quaternary.opacity(0.5),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .help("\(title): \(helpValue ?? value)")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(helpValue ?? value)
}
```

The body begins with `Text("Overview")`, removes `statusText`, removes the
visible `Updates · last 4 weeks` label, and retains concise empty-chart messages
only for unavailable or all-zero history. Compact date values must expose their
full formatted date through `helpValue`.

Declare `DashboardOverviewView` with internal visibility so
`DashboardPanelController` can construct it, keep the chart descriptor private,
and change the panel's apply method to:

```swift
private func apply(_ summary: DashboardSummary) {
    overviewHostingView.rootView = AnyView(DashboardOverviewView(summary: summary))
}
```

- [ ] **Step 4: Expose pending item identity before removing the Items status label**

Add this property and preserve the existing snapshot-acceptance behavior:

```swift
public var pendingID: String? { expectedState?.id }

public func isPending(id: String) -> Bool {
    expectedState?.id == id
}
```

Add assertions to `ManageItemsMutationGateTests`:

```swift
func testExposesPendingItemForRowLocalProgress() {
    var gate = ManageItemsMutationGate()
    gate.begin(id: "tool", enabled: false)

    XCTAssertEqual(gate.pendingID, "tool")
    XCTAssertTrue(gate.isPending(id: "tool"))
    XCTAssertFalse(gate.isPending(id: "other"))

    gate.cancel()
    XCTAssertNil(gate.pendingID)
}
```

- [ ] **Step 5: Replace visible Items status copy with native controls and row state**

Create the refresh button without a visible title:

```swift
private let refreshButton: NSButton = {
    let image = NSImage(
        systemSymbolName: "arrow.clockwise",
        accessibilityDescription: "Refresh items"
    ) ?? NSImage()
    let button = NSButton(image: image, target: nil, action: nil)
    button.isBordered = false
    button.toolTip = "Refresh items"
    button.setAccessibilityLabel("Refresh items")
    return button
}()
```

Remove `statusLabel` from properties, control stacks, loading, apply, and error
paths. Keep redacted native error presentation through `onError`. While
`mutationGate.isPending(id:)` is true, disable that checkbox and show a small
indeterminate `NSProgressIndicator` in its cell; keep table data and category
counts visible. Disable other checkboxes until the shared snapshot accepts the
pending mutation so the existing single-mutation gate cannot be overwritten.

- [ ] **Step 6: Run model and source tests**

Run: `rtk test swift test --filter 'ManageItems(Model|MutationGate)Tests|SourceHygieneTests'`

Expected: all selected tests pass with no persistent Overview or Items helper
copy and with tooltip/accessibility contracts intact.

Run: `rtk swift build --product updatebar-menubar`

Expected: the compact Overview and Items presentation compiles.

---

### Task 6: Update Documentation And Run The Completion Gate

**Files:**
- Modify: `docs/menu-bar.md:15-41`
- Modify: `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift:1392-1410`
- Modify: `openspec/changes/dashboard-sidebar-scan/tasks.md`

- [ ] **Step 1: Write the failing documentation contract**

Replace the old tab wording assertions with:

```swift
XCTAssertTrue(docs.contains("left sidebar"))
XCTAssertTrue(docs.contains("Overview, Items, and Scan & Add"))
XCTAssertTrue(docs.contains("same Dashboard window"))
XCTAssertTrue(docs.contains("Scan only runs when you press Scan"))
XCTAssertTrue(docs.contains("Checking a candidate registers it immediately"))
XCTAssertTrue(docs.contains("unchecking disables it without deleting"))
XCTAssertFalse(docs.contains("Overview and Items tabs"))
XCTAssertFalse(docs.contains("Scan & Add remains a separate panel"))
```

- [ ] **Step 2: Run the documentation test and confirm red**

Run: `rtk test swift test --filter DocumentationSnapshotTests/testMenuBarDocsDescribeCurrentNativeMenuAndUnifiedDashboardWindow`

Expected: FAIL because `docs/menu-bar.md` still describes tabs and a separate
Scan panel.

- [ ] **Step 3: Replace the Dashboard documentation paragraph**

Use this exact behavior description, wrapping lines to match the file:

```markdown
`Dashboard`, `Manage Items`, and `Scan & Add` open the same Dashboard window on
the matching entry in its left sidebar: Overview, Items, and Scan & Add.
Overview shows compact metrics and the four-week update chart. Items lists every
registered item by category with an enable checkbox. Scan only runs when you
press Scan. Checking a candidate registers it immediately as enabled and
untrusted; unchecking disables it without deleting its recipe, approvals, or
state. Supplementary count and control descriptions are available through
native tooltips and accessibility labels.
```

Retain the existing Cmd-Tab, Dock, menu-bar-only activation, build, install, and
troubleshooting documentation around the replaced paragraph.

- [ ] **Step 4: Run focused Swift tests**

Run: `rtk test swift test --filter UpdateBarMenuBarTests`

Expected: all menu-bar model, adapter, routing, source, and accessibility
contracts pass.

Run: `rtk test swift test --filter DocumentationSnapshotTests`

Expected: all documentation contracts pass.

- [ ] **Step 5: Format the touched Swift files**

Run:

```bash
rtk xcrun swift-format format --in-place \
  Sources/UpdateBarMenuBar/ScanListModel.swift \
  Sources/UpdateBarMenuBar/ScanMutationGate.swift \
  Sources/UpdateBarMenuBar/ManageItemsMutationGate.swift \
  Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift \
  Sources/UpdateBarMenuBarApp/DashboardOverviewView.swift \
  Sources/UpdateBarMenuBarApp/DashboardPanelController.swift \
  Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift \
  Sources/UpdateBarMenuBarApp/ScanViewController.swift \
  Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift \
  Tests/UpdateBarMenuBarTests/ScanListModelTests.swift \
  Tests/UpdateBarMenuBarTests/ScanMutationGateTests.swift \
  Tests/UpdateBarMenuBarTests/ManageItemsModelTests.swift \
  Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift \
  Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift
```

Expected: command exits 0 and only formatting changes inside task files.

- [ ] **Step 6: Perform manual macOS QA**

Build and launch:

```bash
rtk swift build --product updatebar-menubar
rtk proxy env UPDATEBAR_BIN=.build/debug/updatebar .build/debug/updatebar-menubar
```

Verify these exact scenarios:

1. Dashboard, Manage Items, and Scan & Add each open the same window on the
   matching sidebar row.
2. Sidebar mouse and keyboard selection swap content without a second window.
3. Opening Scan & Add does not scan; pressing `Scan` does.
4. A new candidate checks to enabled/untrusted immediately.
5. Unchecking changes it to disabled without removing its manifest recipe or
   approvals; rechecking enables the existing recipe.
6. Two different scan rows can mutate independently; one row cannot be toggled
   twice while pending; Scan remains disabled until all row mutations finish.
7. Forced mutation failure restores the checkbox and exposes only redacted
   details.
8. Overview and Items contain no persistent helper sentences; metrics, badges,
   info, and refresh controls expose tooltips and VoiceOver labels.
9. Closing the final Dashboard window returns the app to menu-bar-only mode.

- [ ] **Step 7: Run the repository quality gate**

Run: `rtk Scripts/quality-gate.sh`

Expected: exit 0 after formatting lint, Swift build/tests, script tests, CLI,
menu-bar, TUI, packaging, and smoke checks. Do not claim completion without the
fresh gate tail.

- [ ] **Step 8: Review task-only scope and finish the OpenSpec checklist**

Run: `rtk git diff --stat`

Expected: only the files listed in this plan plus the approved design and plan
documents appear. The pre-existing untracked compact-command-approval documents
remain untouched.

Mark every item in
`openspec/changes/dashboard-sidebar-scan/tasks.md` complete only after the
corresponding code, focused tests, manual QA, and quality gate have passed.
