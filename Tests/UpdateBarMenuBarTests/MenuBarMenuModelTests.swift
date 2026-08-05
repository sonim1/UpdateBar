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
                "Update All",
                "---",
                "Dashboard",
                "Manage Items...",
                "Scan & Add",
                "Settings...",
                "About UpdateBar",
                "Check for Updates...",
                "Quit",
            ])
        XCTAssertEqual(
            Array(model.entries.actions.suffix(2)),
            [.menu(.checkForUpdates), .menu(.quit)]
        )
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

    func testTUIIsHiddenRegardlessOfInstalledTerminals() {
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

        XCTAssertFalse(model.entries.labels.contains("Open TUI"))
        XCTAssertNil(model.entries.submenu(titled: "Open TUI"))
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

        XCTAssertTrue(activeModel.entries.labels.contains("Update [REDACTED]… (0/0)"))
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

    func testActiveUpdateMenuKeepsNavigationAvailable() {
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
            activeActionTitle: "Updating Old Tool"
        )

        // The menu no longer collapses: the outdated-items and approvals
        // sections stay in the menu (previously wiped out entirely by the
        // early-return this task removes), and the footer remains enabled.
        XCTAssertEqual(
            model.entries.labels,
            [
                "Updating Old Tool… (0/0)",
                "Stop After Current",
                "---",
                "Needs attention",
                "1 needs attention",
                "---",
                "Check Now",
                "Refresh Status",
                "Update All",
                "---",
                "Updates (1)",
                "Old Tool 1.0.0 -> 1.1.0",
                "---",
                "Command Approval Required (1)",
                "Fresh Tool",
                "---",
                "Dashboard",
                "Manage Items...",
                "Scan & Add",
                "Settings...",
                "About UpdateBar",
                "Check for Updates...",
                "Quit",
            ])
        XCTAssertEqual(
            model.entries.actions,
            [
                .stopCurrentAction,
                .menu(.overview),
                .menu(.manageItems),
                .menu(.scanAndAdd),
                .menu(.openConfig),
                .menu(.about),
                .menu(.checkForUpdates),
                .menu(.quit),
            ])

        // The rows that would start a second concurrent action are disabled
        // (action: nil) while busy, not hidden.
        XCTAssertNil(model.entries.item(titled: "Check Now")?.action)
        XCTAssertNil(model.entries.item(titled: "Refresh Status")?.action)
        XCTAssertNil(model.entries.item(titled: "Update All")?.action)
        XCTAssertNil(model.entries.item(titled: "Old Tool 1.0.0 -> 1.1.0")?.action)
        XCTAssertNil(model.entries.item(titled: "Fresh Tool")?.action)
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
                "Update All",
                "---",
                "Updates (1)",
                "Old Tool 1.0.0 -> 1.1.0",
                "---",
                "Command Approval Required (1)",
                "Fresh Tool >",
                "---",
                "Errors (1)",
                "Broken Tool: command failed",
                "---",
                "Installed (1)",
                "Ready Tool 2.0.0",
                "---",
                "Dashboard",
                "Manage Items...",
                "Scan & Add",
                "Settings...",
                "About UpdateBar",
                "Check for Updates...",
                "Quit",
            ])
        XCTAssertEqual(
            model.entries.actions,
            [
                .menu(.checkNow),
                .menu(.refreshStatus),
                .menu(.updateAllApprovedOutdated),
                .update(id: "old"),
                .menu(.overview),
                .menu(.manageItems),
                .menu(.scanAndAdd),
                .menu(.openConfig),
                .menu(.about),
                .menu(.checkForUpdates),
                .menu(.quit),
            ])
        XCTAssertTrue(model.entries.labels.contains("Command Approval Required (1)"))
        XCTAssertTrue(model.entries.labels.contains("Fresh Tool >"))
        XCTAssertFalse(model.entries.labels.contains { $0.contains("fresh update") })
        XCTAssertFalse(
            model.entries.actions.contains(.approve(id: "fresh", field: "update.cmd"))
        )
        XCTAssertFalse(
            model.entries.actions.contains(.revoke(id: "fresh", field: "check.cmd"))
        )

        let submenu = model.entries.submenu(titled: "Fresh Tool")
        XCTAssertEqual(submenu?.systemSymbolName, "circle.lefthalf.filled")
        XCTAssertEqual(submenu?.items.map(\.title), ["Approve Update", "Revoke Check"])
        XCTAssertEqual(
            submenu?.items.map(\.action),
            [
                .approve(id: "fresh", field: "update.cmd"),
                .revoke(id: "fresh", field: "check.cmd"),
            ]
        )
        XCTAssertEqual(
            submenu?.items.map(\.systemSymbolName),
            ["circle", "checkmark.circle"]
        )
        XCTAssertEqual(
            submenu?.items.map(\.toolTip),
            [
                "Approves update.cmd for fresh after confirmation.",
                "Revokes check.cmd for fresh after confirmation.",
            ]
        )
        let approveItem = submenu?.items.first
        XCTAssertEqual(
            approveItem?.toolTip,
            "Approves update.cmd for fresh after confirmation."
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
        let revokeItem = submenu?.items.last
        XCTAssertEqual(
            revokeItem?.toolTip,
            "Revokes check.cmd for fresh after confirmation."
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

    func testUpdateAllRunsImmediatelyWithoutConfirmation() {
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

        let updateAllItem = model.entries.item(titled: "Update All")

        XCTAssertEqual(updateAllItem?.toolTip, "Updates all 2 approved outdated items.")
        XCTAssertEqual(updateAllItem?.action, .menu(.updateAllApprovedOutdated))
        XCTAssertNil(updateAllItem?.confirmation)
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

        let runUpdatesItem = model.entries.item(titled: "Update All")

        XCTAssertNil(runUpdatesItem?.action)
        XCTAssertEqual(runUpdatesItem?.toolTip, "No updates available.")
    }

    func testSingleUpdateRunsImmediatelyWithoutConfirmation() {
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

        XCTAssertEqual(updateItem?.toolTip, "Updates old immediately.")
        XCTAssertNil(updateItem?.confirmation)
    }

    func testApprovalMenuRedactsSecretLikeCommandDetails() throws {
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

        let submenu = try XCTUnwrap(model.entries.submenu(titled: "Tool"))
        let approvalItem = try XCTUnwrap(submenu.items.first)

        XCTAssertEqual(approvalItem.title, "Approve Update")
        XCTAssertEqual(
            approvalItem.toolTip,
            "Approves update.cmd for tool after confirmation."
        )
        XCTAssertFalse(model.entries.labels.contains { $0.contains("sk-or-v1-secret-value") })
        XCTAssertFalse(submenu.items.contains { $0.title.contains("[REDACTED]") })
        XCTAssertFalse(submenu.items.contains { $0.title.contains("tool update") })
        XCTAssertFalse(submenu.items.contains { $0.title.contains("OPENROUTER_API_KEY=") })
        XCTAssertFalse(approvalItem.toolTip?.contains("[REDACTED]") ?? true)
        XCTAssertFalse(approvalItem.toolTip?.contains("sk-or-v1-secret-value") ?? true)
        XCTAssertFalse(approvalItem.toolTip?.contains("tool update") ?? true)
        XCTAssertTrue(
            approvalItem.confirmation?.message.contains("[REDACTED] tool update") ?? false
        )
        XCTAssertTrue(
            approvalItem.confirmation?.message.contains("/tmp/[REDACTED]") ?? false
        )
        XCTAssertFalse(
            approvalItem.confirmation?.message.contains("sk-or-v1-secret-value") ?? true
        )
    }

    func testApprovalServiceWithoutCommandFieldsIsOneDisabledRow() throws {
        let state = MenuBarState(
            title: "Needs approval",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: [
                statusItem(id: "empty", name: "Empty Tool", status: .untrusted)
            ],
            errorItems: [],
            okItems: []
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: ["empty": []]
        )

        let emptyItems = model.entries.items(titled: "Empty Tool")
        XCTAssertEqual(emptyItems.count, 1)
        let emptyItem = try XCTUnwrap(emptyItems.first)
        XCTAssertNil(emptyItem.action)
        XCTAssertEqual(emptyItem.systemSymbolName, "questionmark.circle")
        XCTAssertNil(model.entries.submenu(titled: "Empty Tool"))
    }

    func testApprovalOverflowCountsServicesInsteadOfCommandRows() {
        let approvalItems = Array(1...10).map { index in
            statusItem(
                id: "approval-\(index)",
                name: "Approval \(index)",
                status: .untrusted
            )
        }
        let approvals = Dictionary(
            uniqueKeysWithValues: approvalItems.map { item in
                (
                    item.id,
                    [
                        CommandApprovalStatus(
                            field: "check.cmd",
                            approved: false,
                            fingerprint: "fp-\(item.id)",
                            command: "check \(item.id)",
                            cwd: nil
                        )
                    ]
                )
            })
        let state = MenuBarState(
            title: "Needs approval",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: approvalItems,
            errorItems: [],
            okItems: []
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: approvals
        )
        let approvalSubmenus = model.entries.submenus.filter {
            $0.title.hasPrefix("Approval ")
        }

        XCTAssertEqual(approvalSubmenus.count, 8)
        XCTAssertTrue(
            approvalSubmenus.allSatisfy {
                $0.systemSymbolName == "exclamationmark.circle"
            }
        )
        XCTAssertEqual(model.entries.items(titled: "and 2 more").count, 1)
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
                "Dashboard",
                "Manage Items...",
                "Scan & Add",
                "Settings...",
                "About UpdateBar",
                "Check for Updates...",
                "Quit",
            ])
        XCTAssertEqual(
            model.entries.actions,
            [
                .menu(.refreshStatus),
                .menu(.checkNow),
                .menu(.overview),
                .menu(.manageItems),
                .menu(.scanAndAdd),
                .menu(.openConfig),
                .menu(.about),
                .menu(.checkForUpdates),
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
        let state = MenuBarState(
            title: "8 updates",
            badgeValue: "8",
            outdatedItems: outdated,
            approvalItems: [],
            errorItems: errors,
            okItems: installed
        )

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: [:]
        )

        XCTAssertTrue(model.entries.labels.contains("and 1 more"))
        XCTAssertEqual(
            model.entries.labels.filter { $0 == "and 1 more" }.count,
            2
        )
    }

    func testActiveActionKeepsItemRowsAndFooterVisible() {
        var progress = MenuBarItemProgress()
        progress.plannedIDs = ["alpha", "bravo"]
        progress.inFlightIDs = ["alpha"]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: stateWithOutdated(
                ids: ["alpha", "bravo"],
                errorIDs: ["broken"],
                installedIDs: ["ready"]
            ),
            approvalStatuses: [:],
            activeActionTitle: "Updating approved items",
            activeItemProgress: progress
        )

        let titles = model.entries.compactMap { entry -> String? in
            if case .item(let item) = entry { return item.title }
            return nil
        }
        XCTAssertTrue(titles.contains { $0.contains("Updating approved items… (0/2)") })
        XCTAssertTrue(titles.contains("Stop After Current"))
        XCTAssertTrue(titles.contains { $0.contains("alpha") && $0.hasSuffix("— updating…") })
        XCTAssertTrue(titles.contains { $0.contains("bravo") && $0.hasSuffix("— queued") })
        XCTAssertTrue(titles.contains("Quit"), "footer actions must stay visible")
        XCTAssertTrue(
            model.entries.labels.contains("Errors (1)"),
            "the Errors section must still render during an active action")
        XCTAssertTrue(
            model.entries.labels.contains("Installed (1)"),
            "the Installed section must still render during an active action")
    }

    func testActiveActionDisablesItemAndRefreshRowsButNotFooter() {
        var progress = MenuBarItemProgress()
        progress.plannedIDs = ["alpha"]
        progress.inFlightIDs = ["alpha"]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: stateWithOutdated(ids: ["alpha"]),
            approvalStatuses: [:],
            activeActionTitle: "Updating approved items",
            activeItemProgress: progress
        )

        var actionsByTitle: [String: MenuBarMenuItemAction?] = [:]
        for entry in model.entries {
            if case .item(let item) = entry { actionsByTitle[item.title] = item.action }
        }
        XCTAssertNil(actionsByTitle["Check Now"] ?? nil)
        XCTAssertNil(actionsByTitle["Refresh Status"] ?? nil)
        XCTAssertNotNil(actionsByTitle["Quit"] ?? nil)
        XCTAssertEqual(
            actionsByTitle["Stop After Current"] ?? nil, .stopCurrentAction)
    }

    func testStopRequestedShowsStoppingAndDisablesTheStopRow() {
        var progress = MenuBarItemProgress()
        progress.plannedIDs = ["alpha"]
        progress.inFlightIDs = ["alpha"]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: stateWithOutdated(ids: ["alpha"]),
            approvalStatuses: [:],
            activeActionTitle: "Updating approved items",
            activeItemProgress: progress,
            isStopRequested: true
        )

        var stopRow: MenuBarMenuItem?
        for entry in model.entries {
            if case .item(let item) = entry, item.title.hasPrefix("Stopping") { stopRow = item }
        }
        XCTAssertEqual(stopRow?.title, "Stopping after current…")
        XCTAssertNil(stopRow?.action)
    }

    func testFinishedItemsAreMarkedDone() {
        var progress = MenuBarItemProgress()
        progress.plannedIDs = ["alpha"]
        progress.finishedIDs = ["alpha"]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: stateWithOutdated(ids: ["alpha"]),
            approvalStatuses: [:],
            activeActionTitle: "Updating approved items",
            activeItemProgress: progress
        )

        let titles = model.entries.compactMap { entry -> String? in
            if case .item(let item) = entry { return item.title }
            return nil
        }
        XCTAssertTrue(titles.contains { $0.contains("alpha") && $0.hasSuffix("— done") })
    }

    func testActiveActionDisablesApprovalSubmenuRows() {
        let approvals = [
            CommandApprovalStatus(
                field: "update.cmd", approved: false, fingerprint: "abc",
                command: "brew upgrade alpha", cwd: nil
            )
        ]
        let state = MenuBarState(
            title: "Needs attention",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: [
                statusItem(id: "alpha", name: "alpha", status: .untrusted)
            ],
            errorItems: [],
            okItems: []
        )

        var progress = MenuBarItemProgress()
        progress.plannedIDs = ["alpha"]
        progress.inFlightIDs = ["alpha"]

        let busy = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: ["alpha": approvals],
            activeActionTitle: "Updating approved items",
            activeItemProgress: progress
        )
        let idle = MenuBarMenuModelBuilder().makeMenu(
            state: state,
            approvalStatuses: ["alpha": approvals]
        )

        // Idle: the row is actionable. Busy: same row, no action. Checking
        // both directions guards against a regression that unconditionally
        // disables the row (which would make the busy-only assertion pass
        // for the wrong reason).
        XCTAssertNotNil(idle.entries.submenu(titled: "alpha")?.items.first?.action)
        XCTAssertNil(busy.entries.submenu(titled: "alpha")?.items.first?.action)
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

    private func stateWithOutdated(
        ids: [String],
        errorIDs: [String] = [],
        installedIDs: [String] = []
    ) -> MenuBarState {
        MenuBarState(
            title: "\(ids.count) update(s) available",
            badgeValue: String(ids.count),
            outdatedItems: ids.map {
                statusItem(id: $0, name: $0, current: "1.0.0", latest: "1.1.0", status: .outdated)
            },
            approvalItems: [],
            errorItems: errorIDs.map {
                statusItem(id: $0, name: $0, status: .error, error: "boom")
            },
            okItems: installedIDs.map {
                statusItem(id: $0, name: $0, current: "1.0.0", status: .ok)
            }
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

    fileprivate var submenus: [MenuBarSubmenu] {
        compactMap { entry in
            guard case .submenu(let submenu) = entry else { return nil }
            return submenu
        }
    }

    fileprivate func submenu(titled title: String) -> MenuBarSubmenu? {
        submenus.first { $0.title == title }
    }

    fileprivate func item(titled title: String) -> MenuBarMenuItem? {
        items(titled: title).first
    }

    fileprivate func items(titled title: String) -> [MenuBarMenuItem] {
        compactMap { entry in
            guard case .item(let item) = entry, item.title == title else { return nil }
            return item
        }
    }

    fileprivate var hasRepeatedSeparators: Bool {
        zip(self, dropFirst()).contains { lhs, rhs in
            lhs == .separator && rhs == .separator
        }
    }
}
