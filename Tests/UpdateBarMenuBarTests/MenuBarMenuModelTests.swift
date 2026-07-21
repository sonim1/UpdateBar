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
                "Refresh Status",
                "Run Updates",
                "---",
                "Open TUI",
                "Dashboard",
                "Manage Items...",
                "Scan & Add",
                "Open Config",
                "View Logs",
                "Quit",
            ])
        XCTAssertFalse(model.entries.hasRepeatedSeparators)
    }

    func testSingularAttentionCountUsesSingularCopy() {
        let state = MenuBarState(
            title: "Needs attention",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: [
                statusItem(id: "fresh", name: "Fresh Tool", current: "2.0.0", status: .ok)
            ],
            errorItems: [],
            okItems: []
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:]
        )

        XCTAssertTrue(model.entries.labels.contains("1 needs attention"))
        XCTAssertFalse(model.entries.labels.contains("1 need attention"))
    }

    func testOpenTUIBecomesTerminalSubmenuWithIconsAndLastUsedCheck() {
        let state = MenuBarState(
            title: "Up to date",
            badgeValue: nil,
            outdatedItems: [],
            approvalItems: [],
            errorItems: [],
            okItems: []
        )
        let terminals = [
            TUITerminal.fallback,
            TUITerminal(id: "com.googlecode.iterm2", name: "iTerm", launchStyle: .openDocument),
        ]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:],
            installedTerminals: terminals,
            selectedTerminalID: "com.googlecode.iterm2"
        )

        let labels = model.entries.labels
        XCTAssertFalse(labels.contains("Open TUI"))
        XCTAssertTrue(labels.contains("Open TUI >"))

        let submenu = model.entries.submenu(titled: "Open TUI")
        XCTAssertEqual(submenu?.items.map(\.title), ["Terminal", "iTerm"])
        XCTAssertEqual(submenu?.items.map(\.isChecked), [false, true])
        XCTAssertEqual(
            submenu?.items.map(\.iconAppBundleID),
            ["com.apple.Terminal", "com.googlecode.iterm2"]
        )
        XCTAssertEqual(
            submenu?.items.first?.action,
            .openTUIInTerminal(bundleID: "com.apple.Terminal")
        )
    }

    func testOpenTUISubmenuFallsBackToTerminalForUnknownLastUsed() {
        let state = MenuBarState(
            title: "Up to date",
            badgeValue: nil,
            outdatedItems: [],
            approvalItems: [],
            errorItems: [],
            okItems: []
        )
        let terminals = [
            TUITerminal.fallback,
            TUITerminal(id: "com.googlecode.iterm2", name: "iTerm", launchStyle: .openDocument),
        ]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:],
            installedTerminals: terminals,
            selectedTerminalID: "com.example.uninstalled"
        )

        let submenu = model.entries.submenu(titled: "Open TUI")
        XCTAssertEqual(submenu?.items.map(\.isChecked), [true, false])
    }

    func testOpenTUIStaysPlainItemWhenOnlyOneTerminalInstalled() {
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
            approvalStatuses: [:],
            installedTerminals: [TUITerminal.fallback],
            selectedTerminalID: nil
        )

        XCTAssertNil(model.entries.submenu(titled: "Open TUI"))
        XCTAssertTrue(model.entries.labels.contains("Open TUI"))
    }

    func testActionNoticesRedactSecretLikeTitles() {
        let state = MenuBarState(
            title: "Up to date",
            badgeValue: nil,
            outdatedItems: [],
            approvalItems: [],
            errorItems: [],
            okItems: []
        )

        let activeModel = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:],
            activeActionTitle: "Update sk-or-v1-secret-value"
        )
        let finishedModel = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:],
            lastActionNotice: "Finished: Update sk-or-v1-secret-value"
        )

        XCTAssertTrue(activeModel.entries.labels.contains("Running: Update [REDACTED]"))
        XCTAssertTrue(finishedModel.entries.labels.contains("Finished: Update [REDACTED]"))
        XCTAssertFalse(activeModel.entries.labels.contains { $0.contains("sk-or-v1-secret-value") })
        XCTAssertFalse(
            finishedModel.entries.labels.contains { $0.contains("sk-or-v1-secret-value") })
    }

    func testLoadingMenuContainsOnlySafeDashboardAndQuitActions() {
        let model = MenuBarMenuModelBuilder().makeLoadingMenu()

        XCTAssertEqual(
            model.entries.labels,
            [
                "Checking for updates...",
                "---",
                "Dashboard",
                "Quit",
            ])
        XCTAssertEqual(
            model.entries.actions,
            [
                .menu(.overview),
                .menu(.quit),
            ])
    }

    func testActiveActionMenuContainsCancelAndOnlySafeFooterActions() {
        let state = MenuBarState(
            title: "Needs attention",
            badgeValue: "!",
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
                statusItem(id: "fresh", name: "Fresh Tool", status: .untrusted)
            ],
            errorItems: [],
            okItems: []
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:],
            activeActionTitle: "Update Old Tool"
        )

        XCTAssertEqual(
            model.entries.labels,
            [
                "Running: Update Old Tool",
                "Cancel Current Action",
                "---",
                "Dashboard",
                "View Logs",
                "Quit",
            ])
        XCTAssertEqual(
            model.entries.actions,
            [
                .cancelCurrentAction,
                .menu(.overview),
                .menu(.viewLogs),
                .menu(.quit),
            ])
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
                "Refresh Status",
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
                "Dashboard",
                "Manage Items...",
                "Scan & Add",
                "Open Config",
                "View Logs",
                "Quit",
            ])
        XCTAssertEqual(
            model.entries.actions,
            [
                .menu(.checkNow),
                .menu(.refreshStatus),
                .menu(.updateAllApprovedOutdated),
                .update(id: "old"),
                .approve(id: "fresh", field: "update.cmd"),
                .revoke(id: "fresh", field: "check.cmd"),
                .menu(.openTUI),
                .menu(.overview),
                .menu(.manageItems),
                .menu(.scanAndAdd),
                .menu(.openConfig),
                .menu(.viewLogs),
                .menu(.quit),
            ])
        let approveItem = model.entries.item(
            titled: "      Approve update.cmd: fresh update [cwd: /tmp/fresh]"
        )
        XCTAssertEqual(
            approveItem?.toolTip,
            "Approves update.cmd for fresh after confirmation.\nupdate.cmd: fresh   update [cwd: /tmp/fresh]"
        )
        XCTAssertEqual(
            approveItem?.confirmation?.message,
            """
            This approves update.cmd for fresh.

            Command:
            fresh   update

            Working directory:
            /tmp/fresh
            """
        )
        let revokeItem = model.entries.item(titled: "      Revoke check.cmd: fresh check")
        XCTAssertEqual(
            revokeItem?.toolTip,
            "Revokes check.cmd for fresh after confirmation.\ncheck.cmd: fresh check"
        )
        XCTAssertEqual(
            revokeItem?.confirmation?.message,
            """
            This revokes check.cmd for fresh.

            Command:
            fresh check
            """
        )
        XCTAssertFalse(model.entries.hasRepeatedSeparators)
    }

    func testRunUpdatesActionConfirmationSummarizesScope() {
        let state = MenuBarState(
            title: "2 updates",
            badgeValue: "2",
            outdatedItems: [
                statusItem(
                    id: "old",
                    name: "Old Tool",
                    current: "1.0.0",
                    latest: "1.1.0",
                    status: .outdated
                ),
                statusItem(
                    id: "older",
                    name: "Older Tool",
                    current: "2.0.0",
                    latest: "2.1.0",
                    status: .outdated
                ),
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

        XCTAssertEqual(
            runUpdatesItem?.toolTip, "Runs 2 approved outdated items after confirmation.")
        XCTAssertEqual(runUpdatesItem?.confirmation?.title, "Run 2 Updates?")
        XCTAssertEqual(
            runUpdatesItem?.confirmation?.message,
            """
            This runs update commands for 2 approved outdated items.

            Items:
            - Old Tool
            - Older Tool
            """
        )
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

    func testSingleUpdateActionConfirmationIncludesCommandDetailsWhenAvailable() {
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
        let approvals = [
            "old": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: true,
                    fingerprint: "abc",
                    command: "old-tool update",
                    cwd: "/tmp/old"
                )
            ]
        ]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: approvals
        )

        let updateItem = model.entries.item(titled: "Old Tool 1.0.0 -> 1.1.0")

        XCTAssertEqual(
            updateItem?.confirmation?.message,
            """
            This runs the update command for old.

            Command:
            old-tool update

            Working directory:
            /tmp/old
            """
        )
    }

    func testSingleUpdateActionConfirmationRedactsSecretLikeCommandDetails() {
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
        let approvals = [
            "old": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: true,
                    fingerprint: "abc",
                    command: "OPENROUTER_API_KEY=sk-or-v1-secret-value old update",
                    cwd: "/tmp/sk-or-v1-secret-value"
                )
            ]
        ]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: approvals
        )

        let updateItem = model.entries.item(titled: "Old Tool 1.0.0 -> 1.1.0")

        XCTAssertNotNil(updateItem)
        XCTAssertTrue(updateItem?.confirmation?.message.contains("[REDACTED] old update") ?? false)
        XCTAssertTrue(updateItem?.confirmation?.message.contains("/tmp/[REDACTED]") ?? false)
        XCTAssertFalse(updateItem?.confirmation?.message.contains("sk-or-v1-secret-value") ?? true)
        XCTAssertFalse(updateItem?.confirmation?.message.contains("OPENROUTER_API_KEY=") ?? true)
    }

    func testApprovalMenuRedactsSecretLikeCommandDetails() {
        let state = MenuBarState(
            title: "Needs approval",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: [
                statusItem(id: "tool", name: "Tool", status: .untrusted)
            ],
            errorItems: [],
            okItems: []
        )
        let approvals = [
            "tool": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: false,
                    fingerprint: "abc",
                    command: "OPENROUTER_API_KEY=sk-or-v1-secret-value tool update",
                    cwd: "/tmp/sk-or-v1-secret-value"
                )
            ]
        ]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: approvals
        )

        let approvalItem = model.entries.item(
            titled: "      Approve update.cmd: [REDACTED] tool update [cwd: /tmp/[REDACTED]]"
        )

        XCTAssertNotNil(approvalItem)
        XCTAssertFalse(model.entries.labels.contains { $0.contains("sk-or-v1-secret-value") })
        XCTAssertFalse(approvalItem?.toolTip?.contains("sk-or-v1-secret-value") ?? true)
        XCTAssertFalse(
            approvalItem?.confirmation?.message.contains("sk-or-v1-secret-value") ?? true)
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
                "Refresh Status",
                "Check Now",
                "Open TUI",
                "Dashboard",
                "Manage Items...",
                "Scan & Add",
                "Open Config",
                "View Logs",
                "Quit",
            ])
        XCTAssertEqual(
            model.entries.actions,
            [
                .menu(.refreshStatus),
                .menu(.checkNow),
                .menu(.openTUI),
                .menu(.overview),
                .menu(.manageItems),
                .menu(.scanAndAdd),
                .menu(.openConfig),
                .menu(.viewLogs),
                .menu(.quit),
            ])
        XCTAssertFalse(model.entries.hasRepeatedSeparators)
    }

    func testDashboardTitleRoutesOverviewInNormalAndErrorMenus() {
        let state = MenuBarState(
            title: "Up to date",
            badgeValue: nil,
            outdatedItems: [],
            approvalItems: [],
            errorItems: [],
            okItems: []
        )
        let builder = MenuBarMenuModelBuilder()

        let normalMenu = builder.makeMenu(state: state, approvalStatuses: [:])
        let errorMenu = builder.makeErrorMenu(errorDescription: "manifest invalid")

        XCTAssertEqual(
            normalMenu.entries.item(titled: "Dashboard")?.action,
            .menu(.overview)
        )
        XCTAssertEqual(
            errorMenu.entries.item(titled: "Dashboard")?.action,
            .menu(.overview)
        )
        XCTAssertFalse(normalMenu.entries.labels.contains("Overview"))
        XCTAssertFalse(errorMenu.entries.labels.contains("Overview"))
    }

    func testErrorRecoveryMenuRedactsSecretLikeValues() {
        let model = MenuBarMenuModelBuilder().makeErrorMenu(
            errorDescription: "failed with OPENROUTER_API_KEY=sk-or-v1-secret-value"
        )

        XCTAssertTrue(model.entries.labels.contains("failed with [REDACTED]"))
        XCTAssertFalse(model.entries.labels.contains { $0.contains("sk-or-v1-secret-value") })
        XCTAssertFalse(model.entries.labels.contains { $0.contains("OPENROUTER_API_KEY=") })
    }

    func testStatusErrorItemsRedactSecretLikeValues() {
        let state = MenuBarState(
            title: "1 error",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: [],
            errorItems: [
                statusItem(
                    id: "broken",
                    name: "Broken Tool",
                    status: .error,
                    error: "failed with sk-or-v1-secret-value"
                )
            ],
            okItems: []
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:]
        )

        XCTAssertTrue(model.entries.labels.contains("Broken Tool: failed with [REDACTED]"))
        XCTAssertFalse(model.entries.labels.contains { $0.contains("sk-or-v1-secret-value") })
    }

    func testMenuItemTitlesRedactSecretLikeStatusFields() {
        let state = MenuBarState(
            title: "Sensitive state",
            badgeValue: "!",
            outdatedItems: [
                statusItem(
                    id: "old",
                    name: "Old sk-or-v1-secret-value",
                    current: "1.0.0-sk-or-v1-secret-value",
                    latest: "1.1.0-sk-or-v1-secret-value",
                    status: .outdated
                )
            ],
            approvalItems: [],
            errorItems: [
                statusItem(
                    id: "broken",
                    name: "Broken sk-or-v1-secret-value",
                    status: .error,
                    error: "failed with sk-or-v1-secret-value"
                )
            ],
            okItems: [
                statusItem(
                    id: "ready",
                    name: "Ready sk-or-v1-secret-value",
                    current: "2.0.0-sk-or-v1-secret-value",
                    status: .ok
                )
            ]
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:]
        )

        XCTAssertTrue(
            model.entries.labels.contains(
                "Old [REDACTED] 1.0.0-[REDACTED] -> 1.1.0-[REDACTED]"
            ))
        XCTAssertTrue(model.entries.labels.contains("Broken [REDACTED]: failed with [REDACTED]"))
        XCTAssertTrue(model.entries.labels.contains("Ready [REDACTED] 2.0.0-[REDACTED]"))
        XCTAssertFalse(model.entries.labels.contains { $0.contains("sk-or-v1-secret-value") })
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
            case .submenu(let submenu):
                return "\(submenu.title) >"
            }
        }
    }

    fileprivate var actions: [MenuBarMenuItemAction] {
        compactMap { entry in
            guard case .item(let item) = entry else { return nil }
            return item.action
        }
    }

    fileprivate func submenu(titled title: String) -> MenuBarSubmenu? {
        compactMap { entry in
            guard case .submenu(let submenu) = entry else { return nil }
            return submenu
        }.first { $0.title == title }
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
