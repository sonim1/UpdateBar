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
                "Run Updates",
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
                "Run Updates",
                "---",
                "Updates (1)",
                "Old Tool 1.0.0 -> 1.1.0",
                "---",
                "Needs Approval (1)",
                "  Fresh Tool (2 commands)",
                "      Approve update.cmd: fresh update [cwd: /tmp/fresh]",
                "      Revoke check.cmd: fresh check",
                "---",
                "Errors (1)",
                "Broken Tool: command failed",
                "---",
                "Installed (1)",
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

    func testRunUpdatesActionExplainsConfirmation() {
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
            approvalItems: [],
            errorItems: [],
            okItems: []
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:]
        )

        let runUpdatesItem = model.entries.item(titled: "Run Updates")

        XCTAssertEqual(runUpdatesItem?.toolTip, "Runs approved outdated items after confirmation.")
    }

    func testRunUpdatesIsDisabledWhenNothingIsOutdated() {
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

        let runUpdatesItem = model.entries.item(titled: "Run Updates")

        XCTAssertNil(runUpdatesItem?.action)
        XCTAssertEqual(runUpdatesItem?.toolTip, "No updates available.")
    }

    func testSingleUpdateActionExplainsConfirmation() {
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
            approvalItems: [],
            errorItems: [],
            okItems: []
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:]
        )

        let updateItem = model.entries.item(titled: "Old Tool 1.0.0 -> 1.1.0")

        XCTAssertEqual(updateItem?.toolTip, "Runs old after confirmation.")
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

    func testBuildsCompactMenuWithOverflowSummaries() {
        let outdated = Array(1...8).map {
            statusItem(
                id: "old-\($0)",
                name: "Tool-\($0)",
                current: "1.0.\($0)",
                latest: "1.1.\($0)",
                status: .outdated
            )
        }
        let errors = Array(1...7).map {
            statusItem(
                id: "error-\($0)",
                name: "Err-\($0)",
                status: .error,
                error: "boom"
            )
        }
        let installed = Array(1...7).map {
            statusItem(
                id: "ok-\($0)",
                name: "Ok-\($0)",
                current: "2.0.\($0)",
                status: .ok
            )
        }
        let approvals = [
            "approve": Array(1...10).map { index in
                CommandApprovalStatus(
                    field: "field-\(index)",
                    approved: index.isMultiple(of: 2),
                    fingerprint: "fp-\(index)",
                    command: "run cmd-\(index)",
                    cwd: nil
                )
            }
        ]

        let state = MenuBarState(
            title: "8 updates",
            badgeValue: "8",
            outdatedItems: outdated,
            approvalItems: [
                statusItem(id: "approve", name: "Approve Tool", status: .ok)
            ],
            errorItems: errors,
            okItems: installed
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: approvals
        )

        XCTAssertTrue(model.entries.labels.contains("and 1 more"))
        XCTAssertEqual(
            model.entries.labels.filter { $0 == "and 1 more" }.count,
            2
        )
        XCTAssertTrue(model.entries.labels.contains(where: { $0.contains("and 8 more") }))
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

    fileprivate func item(titled title: String) -> MenuBarMenuItem? {
        compactMap { entry in
            guard case .item(let item) = entry else { return nil }
            return item
        }.first { $0.title == title }
    }

    fileprivate var hasRepeatedSeparators: Bool {
        zip(self, dropFirst()).contains { lhs, rhs in
            lhs == .separator && rhs == .separator
        }
    }
}
