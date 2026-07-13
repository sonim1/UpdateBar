# Menubar Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the primary native status-item menu with a system-material popover that follows native macOS menu density while keeping the detailed dashboard as a separate window.

**Architecture:** A pure presentation builder in UpdateBarMenuBar maps existing state and approval data into testable rows. UpdateBarMenuBarApp hosts a compact SwiftUI view in a transient NSPopover and routes its actions back through the existing action coordinator and panel controllers. The current NSMenu remains only as an error fallback. View and controller share one 340-by-520-point layout size.

**Tech Stack:** Swift 6, AppKit, SwiftUI, XCTest, macOS 13+

---

## File Map

- Create Sources/UpdateBarMenuBar/MenuBarPopoverModel.swift: immutable popover presentation data and mapping.
- Create Tests/UpdateBarMenuBarTests/MenuBarPopoverModelTests.swift: mapping, redaction, and action tests.
- Create Sources/UpdateBarMenuBarApp/MenuBarPopoverView.swift: compact segmented navigation, borderless rows, and vertical menu-style commands.
- Create Sources/UpdateBarMenuBarApp/MenuBarPopoverController.swift: NSPopover lifecycle and system material hosting.
- Modify Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift: guard the native menu layout and shared compact size.
- Modify Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift: status-button routing, live model updates, and action dispatch.
- Modify Sources/UpdateBarMenuBarApp/DashboardPanelController.swift: separate modern dashboard layout and Updates copy.

The approved native-menu refinement is limited to the popover view, its shared size in the controller, focused source hygiene coverage, and documentation. It does not change presentation models, services, action routing, or the standalone dashboard.

### Task 1: Build the Popover Presentation Model

**Files:**
- Create: Sources/UpdateBarMenuBar/MenuBarPopoverModel.swift
- Create: Tests/UpdateBarMenuBarTests/MenuBarPopoverModelTests.swift

- [ ] **Step 1: Write the failing model tests**

Create tests covering counts, last-check time, update rows, approval actions, active-action state, and redaction:

~~~swift
import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class MenuBarPopoverModelTests: XCTestCase {
    func testBuildsSummaryAndActionRows() {
        let checked = Date(timeIntervalSince1970: 1_783_080_000)
        let old = item(
            id: "old", name: "Old Tool", current: "1.0", latest: "1.1",
            status: .outdated, lastChecked: checked
        )
        let approval = item(id: "fresh", name: "Fresh Tool", status: .untrusted)
        let error = item(id: "broken", name: "Broken Tool", status: .error)
        let state = MenuBarState(
            title: "1 update",
            badgeValue: "1",
            outdatedItems: [old],
            approvalItems: [approval],
            errorItems: [error],
            okItems: [],
            allItems: [old, approval, error]
        )
        let approvals = [
            "fresh": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: false,
                    fingerprint: "fp",
                    command: "fresh update",
                    cwd: nil
                )
            ]
        ]

        let model = MenuBarPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: approvals
        )

        XCTAssertEqual(model.updateCount, 1)
        XCTAssertEqual(model.approvalCount, 1)
        XCTAssertEqual(model.errorCount, 1)
        XCTAssertEqual(model.trackedItemCount, 3)
        XCTAssertEqual(model.lastChecked, checked)
        XCTAssertEqual(model.updates.first?.detail, "1.0 -> 1.1")
        XCTAssertEqual(model.updates.first?.action, .update(id: "old"))
        XCTAssertEqual(model.errors.first?.detail, "failed")
        XCTAssertEqual(
            model.approvals.first?.action,
            .approve(id: "fresh", field: "update.cmd")
        )
    }

    func testRedactsApprovalDetailsAndExposesRunningState() {
        let approval = item(id: "fresh", name: "Fresh Tool", status: .untrusted)
        let state = MenuBarState(
            title: "Needs attention",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: [approval],
            errorItems: [],
            okItems: [],
            allItems: [approval]
        )
        let approvals = [
            "fresh": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: false,
                    fingerprint: "fp",
                    command: "OPENROUTER_API_KEY=sk-or-v1-secret-value fresh update",
                    cwd: nil
                )
            ]
        ]

        let model = MenuBarPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: approvals,
            activeActionTitle: "Update sk-or-v1-secret-value"
        )

        XCTAssertEqual(model.activeActionTitle, "Update [REDACTED]")
        XCTAssertTrue(model.approvals.first?.detail.contains("[REDACTED]") == true)
        XCTAssertFalse(model.approvals.first?.detail.contains("sk-or-v1-secret-value") == true)
    }

    private func item(
        id: String,
        name: String,
        current: String? = nil,
        latest: String? = nil,
        status: ItemStatus,
        lastChecked: Date? = nil
    ) -> StatusItem {
        StatusItem(
            id: id,
            name: name,
            category: "cli",
            current: current,
            latest: latest,
            status: status,
            pinned: false,
            lastChecked: lastChecked,
            error: status == .error ? "failed" : nil
        )
    }
}
~~~

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

~~~bash
rtk test swift test --filter MenuBarPopoverModelTests
~~~

Expected: compilation fails because MenuBarPopoverModelBuilder does not exist.

- [ ] **Step 3: Implement the minimal presentation model**

Create public Equatable and Sendable model types:

~~~swift
import Foundation
import UpdateBarCore

public struct MenuBarPopoverRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var stateLabel: String
    public var action: MenuBarMenuItemAction?
    public var confirmation: MenuBarActionConfirmation?
}

public struct MenuBarPopoverModel: Equatable, Sendable {
    public var title: String
    public var trackedItemCount: Int
    public var updateCount: Int
    public var approvalCount: Int
    public var errorCount: Int
    public var lastChecked: Date?
    public var activeActionTitle: String?
    public var lastActionNotice: String?
    public var errorMessage: String?
    public var updates: [MenuBarPopoverRow]
    public var approvals: [MenuBarPopoverRow]
    public var errors: [MenuBarPopoverRow]
    public var terminals: [TUITerminal]
    public var selectedTerminalID: String?
}

public struct MenuBarPopoverModelBuilder: Sendable {
    public init() {}

    public func makeModel(
        state: MenuBarState,
        approvalStatuses: [String: [CommandApprovalStatus]],
        activeActionTitle: String? = nil,
        lastActionNotice: String? = nil,
        errorDescription: String? = nil,
        installedTerminals: [TUITerminal] = [],
        selectedTerminalID: String? = nil
    ) -> MenuBarPopoverModel {
        let menu = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: approvalStatuses,
            activeActionTitle: activeActionTitle,
            lastActionNotice: lastActionNotice,
            installedTerminals: installedTerminals,
            selectedTerminalID: selectedTerminalID
        )
        let sourceItems = state.allItems.isEmpty
            ? state.outdatedItems + state.approvalItems + state.errorItems + state.okItems
            : state.allItems
        let trackedIDs = Set(sourceItems.map(\.id))
        let updates = state.outdatedItems.map { item in
            let action = MenuBarMenuItemAction.update(id: item.id)
            let source = menu.item(for: action)
            return MenuBarPopoverRow(
                id: "update-\(item.id)",
                title: item.name,
                detail: "\(item.current ?? "?") -> \(item.latest ?? "?")",
                stateLabel: "Ready",
                action: action,
                confirmation: source?.confirmation
            )
        }
        let approvals = state.approvalItems.flatMap { item in
            let statuses = approvalStatuses[item.id] ?? []
            if statuses.isEmpty {
                return [
                    MenuBarPopoverRow(
                        id: "approval-\(item.id)",
                        title: item.name,
                        detail: "No command fields",
                        stateLabel: "Needs approval",
                        action: nil,
                        confirmation: nil
                    )
                ]
            }
            return statuses.map { approval in
                let action: MenuBarMenuItemAction = approval.approved
                    ? .revoke(id: item.id, field: approval.field)
                    : .approve(id: item.id, field: approval.field)
                return MenuBarPopoverRow(
                    id: "approval-\(item.id)-\(approval.field)",
                    title: item.name,
                    detail: SecretRedactor.redact(
                        "\(approval.field): \(approval.command)"
                    ),
                    stateLabel: approval.approved ? "Approved" : "Needs approval",
                    action: action,
                    confirmation: menu.item(for: action)?.confirmation
                )
            }
        }
        let errors = state.errorItems.map { item in
            MenuBarPopoverRow(
                id: "error-\(item.id)",
                title: item.name,
                detail: SecretRedactor.redact(item.error ?? "Unknown error"),
                stateLabel: "Error",
                action: nil,
                confirmation: nil
            )
        }
        return MenuBarPopoverModel(
            title: state.title,
            trackedItemCount: trackedIDs.count,
            updateCount: state.outdatedItems.count,
            approvalCount: state.approvalItems.count,
            errorCount: state.errorItems.count,
            lastChecked: sourceItems.compactMap(\.lastChecked).max(),
            activeActionTitle: activeActionTitle.map(SecretRedactor.redact),
            lastActionNotice: lastActionNotice.map(SecretRedactor.redact),
            errorMessage: errorDescription.map(SecretRedactor.redact),
            updates: updates,
            approvals: approvals,
            errors: errors,
            terminals: installedTerminals,
            selectedTerminalID: selectedTerminalID
        )
    }
}
~~~

Add this private helper in the same file to retrieve existing confirmation metadata:

~~~swift
private extension MenuBarMenuModel {
    func item(for action: MenuBarMenuItemAction) -> MenuBarMenuItem? {
        entries.compactMap { entry in
            guard case .item(let item) = entry, item.action == action else {
                return nil
            }
            return item
        }.first
    }
}
~~~

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

~~~bash
rtk test swift test --filter MenuBarPopoverModelTests
~~~

Expected: all MenuBarPopoverModelTests pass.

### Task 2: Build the SwiftUI Popover Surface

**Files:**
- Create: Sources/UpdateBarMenuBarApp/MenuBarPopoverView.swift

- [ ] **Step 1: Create the three-tab SwiftUI view**

Implement a fixed 340-by-520-point view with:

- A shared `MenuBarPopoverLayout.size` used by both SwiftUI and `NSPopover`.
- Overview, Updates, and Approvals in a compact native segmented `Picker`.
- A two-row header showing UpdateBar, tracked count, concise status, and relative last-check time.
- One borderless count summary labeled Updates, Approvals, and Errors.
- Scrollable borderless update and approval rows capped by the available popover height.
- Redacted status and error rows with text labels, not color alone or persistent card fills.
- Full-width vertical menu-style rows for Open Dashboard, Manage Items, Open TUI, Refresh, Settings, About, More, and Quit.
- A More menu containing Check Now, Run Updates, Scan & Add, and View Logs so existing commands remain reachable.
- Cancel Current Action while an action is running.
- Open TUI becomes a Menu when multiple installed terminals are present and marks the selected terminal.

Use this public boundary:

~~~swift
struct MenuBarPopoverView: View {
    let model: MenuBarPopoverModel
    let onItemAction: (MenuBarPopoverRow) -> Void
    let onMenuAction: (MenuBarMenuAction) -> Void
    let onAbout: () -> Void

    @State private var selectedTab: MenuBarPopoverTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
            Divider()
            commandList
        }
        .frame(
            width: MenuBarPopoverLayout.size.width,
            height: MenuBarPopoverLayout.size.height
        )
        .background(Color.clear)
    }
}
~~~

Use Button for commands, Menu for secondary commands, Label with SF Symbols, native separators, and secondary text for details. Persistent tile and card backgrounds are prohibited; a subtle hover fill is allowed for actionable rows. Add accessibility labels that include both title and state.

- [ ] **Step 2: Compile the app target**

Run:

~~~bash
rtk err swift build --target UpdateBarMenuBarApp
~~~

Expected: the target builds with no errors.

### Task 3: Host the View in a Native System-Material Popover

**Files:**
- Create: Sources/UpdateBarMenuBarApp/MenuBarPopoverController.swift
- Modify: Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift

- [ ] **Step 1: Add the popover controller**

Create an @MainActor controller that owns one transient NSPopover:

~~~swift
@MainActor
final class MenuBarPopoverController {
    private let popover = NSPopover()

    init() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = MenuBarPopoverLayout.size
    }

    var isShown: Bool { popover.isShown }

    func toggle(
        relativeTo button: NSStatusBarButton,
        model: MenuBarPopoverModel,
        onItemAction: @escaping (MenuBarPopoverRow) -> Void,
        onMenuAction: @escaping (MenuBarMenuAction) -> Void,
        onAbout: @escaping () -> Void
    ) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        update(
            model: model,
            onItemAction: onItemAction,
            onMenuAction: onMenuAction,
            onAbout: onAbout
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func close() {
        popover.performClose(nil)
    }
}
~~~

In update(...), host MenuBarPopoverView in NSHostingView inside NSVisualEffectView with material .popover, blendingMode .behindWindow, and state .followsWindowActiveState. Use constraints to pin the hosting view to all edges. Do not hard-code opacity or blur values.

- [ ] **Step 2: Route the status button to the controller**

In applicationDidFinishLaunching:

~~~swift
statusButton.target = self
statusButton.action = #selector(togglePopover(_:))
statusButton.sendAction(on: [.leftMouseUp])
statusItem?.menu = nil
~~~

Add MenuBarPopoverModelBuilder and MenuBarPopoverController properties. Replace normal rebuildMenu() assignment with:

~~~swift
private func refreshMenuBarPresentation() {
    guard let statusItem else { return }
    statusItem.menu = nil
    // Preserve the existing title and accessibility-label logic.
    if popoverController.isShown {
        popoverController.update(
            model: makePopoverModel(),
            onItemAction: handlePopoverItem,
            onMenuAction: handlePopoverMenuAction,
            onAbout: showAbout
        )
    }
}
~~~

Keep makeMenu(from:) and the NSMenu selector adapters for showError(_:) only.

- [ ] **Step 3: Dispatch existing actions without duplicating service logic**

Close the popover before dispatch. Map MenuBarMenuAction values to the existing methods and map row actions to the existing update, approve, revoke, cancel, and terminal methods. Preserve each row's MenuBarActionConfirmation and pass it through confirm(_:). When a terminal is selected, persist its bundle identifier with the existing TUITerminalBundleID default before launching it.

Use NSApp.orderFrontStandardAboutPanel(nil) for About UpdateBar.

- [ ] **Step 4: Restore normal popover behavior after an error refresh**

Store a redacted lastPopoverError string in UpdateBarMenuBarApp. Clear it after a successful refresh and pass it to MenuBarPopoverModelBuilder. showError(_:) updates this string and the visible popover so Refresh and Settings remain available. Keep makeErrorMenu(errorDescription:) as the native fallback if the popover controller cannot be presented. After using that fallback, the next successful refresh sets statusItem.menu back to nil and restores the status-button target and action.

- [ ] **Step 5: Build and run focused tests**

Run:

~~~bash
rtk test swift test --filter UpdateBarMenuBarTests
rtk err swift build --target UpdateBarMenuBarApp
~~~

Expected: tests pass and the app target builds.

### Task 4: Polish the Separate Dashboard (Original Scope, Unchanged by Refinement)

**Files:**
- Modify: Sources/UpdateBarMenuBarApp/DashboardPanelController.swift

- [ ] **Step 1: Update the standalone dashboard layout**

Keep DashboardSummary and DashboardModel unchanged. Replace the single horizontal tile row with a responsive two-column LazyVGrid, change Pending Updates to Updates, add a compact UpdateBar header, and keep the 28-day Chart below the summary.

Use system colors and quaternary fills:

~~~swift
private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
]

var body: some View {
    VStack(alignment: .leading, spacing: 18) {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("UpdateBar")
                    .font(.title2.weight(.semibold))
                Text("Update activity and current status")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Manage Items...", action: onOpenItems)
        }
        LazyVGrid(columns: columns, spacing: 12) {
            tile(title: "Updates", value: "\(summary.pendingUpdates)", symbol: "arrow.down.circle")
            tile(title: "Awaiting Approval", value: "\(summary.approvalsWaiting)", symbol: "checkmark.shield")
            tile(title: "Last Checked", value: shortDate(summary.lastChecked), symbol: "clock")
            tile(title: "Last Updated", value: shortDate(summary.lastUpdated), symbol: "checkmark.circle")
        }
        Text("Updates · last 4 weeks")
            .font(.headline)
        updatesChart
    }
    .padding(20)
    .frame(minWidth: 620, minHeight: 420)
}
~~~

Change the panel to a normal titled, closable, resizable, miniaturizable window sized near 720 by 520. Keep showWindowAndReload() behavior intact.

- [ ] **Step 2: Build the app target**

Run:

~~~bash
rtk err swift build --target UpdateBarMenuBarApp
~~~

Expected: the target builds with no errors.

### Task 5: Verify Behavior and Regressions

**Files:**
- Verify only; no production edits unless a test exposes a defect in the changed files.

- [ ] **Step 1: Run all tests**

Run:

~~~bash
rtk test swift test
~~~

Expected: all tests pass.

- [ ] **Step 2: Build the release executable**

Run:

~~~bash
rtk err swift build -c release --product updatebar-menubar
~~~

Expected: release build succeeds.

- [ ] **Step 3: Launch and inspect the status item**

Launch the debug executable, click the UpdateBar status item, and verify:

- the popover anchors under the icon;
- the popover remains fixed at 340 by 520 points across tabs and refreshes;
- system material changes with light and dark appearance;
- Overview, Updates, and Approvals switch without resizing;
- Escape and outside click dismiss it;
- Refresh updates both badge and visible content;
- update and approval rows retain confirmation dialogs;
- Open Dashboard closes the popover and opens the standalone window;
- Scan & Add, View Logs, terminal selection, Settings, About, and Quit remain reachable;
- the native error menu appears if service loading fails.

- [ ] **Step 4: Check accessibility and screen edges**

Verify keyboard focus, VoiceOver labels, Reduce Transparency, and placement when the status item is near either edge of the active display.

- [ ] **Step 5: Review the final diff**

Run:

~~~bash
rtk git diff --check
rtk git status --short
~~~

Expected: no whitespace errors; only planned files plus pre-existing user changes are present.
