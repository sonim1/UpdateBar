import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class MenuBarMenuModelTests: XCTestCase {
    func testBuildsCompactMenuForFreshStateWithoutRepeatedSeparators() {
        let state = MenuBarState(
            title: "Up to date",
            badgeValue: nil,
            outdatedItems: [],
            approvalItems: [],
            errorItems: [],
            okItems: []
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:]
        )

        XCTAssertEqual(
            model.entries.labels,
            [
                "Up to date",
                "---",
                "Check Now",
                "Update All Approved Outdated",
                "---",
                "Open TUI",
                "Open Config",
                "View Logs",
                "Quit",
            ])
        XCTAssertFalse(model.entries.hasRepeatedSeparators)
    }

    func testBuildsActionableSectionsForUpdatesApprovalsErrorsAndInstalledItems() {
        let state = MenuBarState(
            title: "1 update",
            badgeValue: "1",
            outdatedItems: [
                statusItem(
                    id: "old",
                    name: "Old Tool",
                    current: "1.0.0",
                    latest: "1.1.0",
                    status: .outdated
                )
            ],
            approvalItems: [
                statusItem(id: "fresh", name: "Fresh Tool", current: "2.0.0", status: .ok)
            ],
            errorItems: [
                statusItem(
                    id: "broken", name: "Broken Tool", status: .error, error: "command failed")
            ],
            okItems: [
                statusItem(id: "ready", name: "Ready Tool", current: "2.0.0", status: .ok)
            ]
        )
        let approvals = [
            "fresh": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: false,
                    fingerprint: "abc",
                    command: "fresh   update",
                    cwd: "/tmp/fresh"
                ),
                CommandApprovalStatus(
                    field: "check.cmd",
                    approved: true,
                    fingerprint: "def",
                    command: "fresh check",
                    cwd: nil
                ),
            ]
        ]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: approvals
        )

        XCTAssertEqual(
            model.entries.labels,
            [
                "1 update",
                "2 need attention",
                "---",
                "Check Now",
                "Update All Approved Outdated",
                "---",
                "Updates",
                "Old Tool 1.0.0 -> 1.1.0",
                "---",
                "Needs Approval",
                "Approve update.cmd for Fresh Tool: fresh update [cwd: /tmp/fresh]",
                "Revoke check.cmd for Fresh Tool: fresh check",
                "---",
                "Errors",
                "Broken Tool: command failed",
                "---",
                "Installed",
                "Ready Tool 2.0.0",
                "---",
                "Open TUI",
                "Open Config",
                "View Logs",
                "Quit",
            ])
        XCTAssertEqual(
            model.entries.actions,
            [
                .menu(.checkNow),
                .menu(.updateAllApprovedOutdated),
                .update(id: "old"),
                .approve(id: "fresh", field: "update.cmd"),
                .revoke(id: "fresh", field: "check.cmd"),
                .menu(.openTUI),
                .menu(.openConfig),
                .menu(.viewLogs),
                .menu(.quit),
            ])
        XCTAssertFalse(model.entries.hasRepeatedSeparators)
    }

    func testBuildsErrorRecoveryMenu() {
        let model = MenuBarMenuModelBuilder().makeErrorMenu(
            errorDescription: "manifest invalid"
        )

        XCTAssertEqual(
            model.entries.labels,
            [
                "UpdateBar Error",
                "manifest invalid",
                "---",
                "Check Now",
                "Open TUI",
                "Open Config",
                "View Logs",
                "Quit",
            ])
        XCTAssertEqual(
            model.entries.actions,
            [
                .menu(.checkNow),
                .menu(.openTUI),
                .menu(.openConfig),
                .menu(.viewLogs),
                .menu(.quit),
            ])
        XCTAssertFalse(model.entries.hasRepeatedSeparators)
    }

    private func statusItem(
        id: String,
        name: String,
        current: String? = nil,
        latest: String? = nil,
        status: ItemStatus,
        error: String? = nil
    ) -> StatusItem {
        StatusItem(
            id: id,
            name: name,
            category: "cli",
            current: current,
            latest: latest,
            status: status,
            pinned: false,
            lastChecked: nil,
            error: error
        )
    }
}

extension Array where Element == MenuBarMenuEntry {
    fileprivate var labels: [String] {
        map { entry in
            switch entry {
            case .separator:
                return "---"
            case .item(let item):
                return item.title
            }
        }
    }

    fileprivate var actions: [MenuBarMenuItemAction] {
        compactMap { entry in
            guard case .item(let item) = entry else { return nil }
            return item.action
        }
    }

    fileprivate var hasRepeatedSeparators: Bool {
        zip(self, dropFirst()).contains { lhs, rhs in
            lhs == .separator && rhs == .separator
        }
    }
}
