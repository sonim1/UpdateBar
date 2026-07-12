import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class MenuBarPopoverModelTests: XCTestCase {
    func testBuildsSummaryAndRows() {
        let earlier = Date(timeIntervalSince1970: 1_783_080_000)
        let latest = Date(timeIntervalSince1970: 1_783_083_600)
        let outdated = item(
            id: "old",
            name: "Old Tool",
            current: "1.0",
            latest: "1.1",
            status: .outdated,
            lastChecked: earlier
        )
        let approval = item(
            id: "fresh",
            name: "Fresh Tool",
            status: .untrusted,
            lastChecked: latest
        )
        let error = item(
            id: "broken",
            name: "Broken Tool",
            status: .error,
            lastChecked: earlier,
            error: "command failed"
        )
        let state = MenuBarState(
            title: "1 update",
            badgeValue: "1",
            outdatedItems: [outdated],
            approvalItems: [approval],
            errorItems: [error],
            okItems: [],
            allItems: [outdated, approval, error]
        )
        let approvals = [
            "old": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: true,
                    fingerprint: "old-fp",
                    command: "old update",
                    cwd: "/tmp/old"
                )
            ],
            "fresh": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: false,
                    fingerprint: "fresh-fp",
                    command: "fresh update",
                    cwd: nil
                )
            ],
        ]
        let terminals = [
            TUITerminal.fallback,
            TUITerminal(
                id: "com.googlecode.iterm2",
                name: "iTerm",
                launchStyle: .openDocument
            ),
        ]

        let model = MenuBarPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: approvals,
            installedTerminals: terminals,
            selectedTerminalID: "com.googlecode.iterm2"
        )

        XCTAssertEqual(model.title, "1 update")
        XCTAssertEqual(model.trackedItemCount, 3)
        XCTAssertEqual(model.updateCount, 1)
        XCTAssertEqual(model.approvalCount, 1)
        XCTAssertEqual(model.errorCount, 1)
        XCTAssertEqual(model.lastChecked, latest)
        XCTAssertEqual(model.terminals, terminals)
        XCTAssertEqual(model.selectedTerminalID, "com.googlecode.iterm2")

        XCTAssertEqual(model.updates.first?.title, "Old Tool")
        XCTAssertEqual(model.updates.first?.detail, "1.0 -> 1.1")
        XCTAssertEqual(model.updates.first?.stateLabel, "Ready")
        XCTAssertEqual(model.updates.first?.action, .update(id: "old"))
        XCTAssertEqual(
            model.updates.first?.confirmation?.message,
            """
            This runs the update command for old.

            Command:
            old update

            Working directory:
            /tmp/old
            """
        )

        XCTAssertEqual(model.approvals.first?.title, "Fresh Tool")
        XCTAssertEqual(model.approvals.first?.detail, "update.cmd: fresh update")
        XCTAssertEqual(model.approvals.first?.stateLabel, "Needs approval")
        XCTAssertEqual(
            model.approvals.first?.action,
            .approve(id: "fresh", field: "update.cmd")
        )
        XCTAssertEqual(
            model.approvals.first?.confirmation?.title,
            "Approve update.cmd?"
        )

        XCTAssertEqual(model.errors.first?.title, "Broken Tool")
        XCTAssertEqual(model.errors.first?.detail, "command failed")
        XCTAssertEqual(model.errors.first?.stateLabel, "Error")
        XCTAssertNil(model.errors.first?.action)
        XCTAssertNil(model.errors.first?.confirmation)
    }

    func testApprovedCommandMapsToRevokeAction() {
        let approval = item(id: "tool", name: "Tool", status: .untrusted)
        let state = state(approvalItems: [approval], allItems: [approval])
        let statuses = [
            "tool": [
                CommandApprovalStatus(
                    field: "check.cmd",
                    approved: true,
                    fingerprint: "fp",
                    command: "tool check",
                    cwd: nil
                )
            ]
        ]

        let model = MenuBarPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: statuses
        )

        XCTAssertEqual(model.approvals.first?.stateLabel, "Approved")
        XCTAssertEqual(
            model.approvals.first?.action,
            .revoke(id: "tool", field: "check.cmd")
        )
        XCTAssertEqual(model.approvals.first?.confirmation?.title, "Revoke check.cmd?")
    }

    func testRedactsPresentationStrings() {
        let secret = "sk-or-v1-secret-value"
        let outdated = item(
            id: "old",
            name: "Old \(secret)",
            current: "1.0-\(secret)",
            latest: "1.1-\(secret)",
            status: .outdated
        )
        let approval = item(id: "fresh", name: "Fresh Tool", status: .untrusted)
        let error = item(
            id: "broken",
            name: "Broken Tool",
            status: .error,
            error: "failed with \(secret)"
        )
        let state = state(
            outdatedItems: [outdated],
            approvalItems: [approval],
            errorItems: [error],
            allItems: [outdated, approval, error]
        )
        let statuses = [
            "fresh": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: false,
                    fingerprint: "fp",
                    command: "OPENROUTER_API_KEY=\(secret) fresh update",
                    cwd: "/tmp/\(secret)"
                )
            ]
        ]

        let model = MenuBarPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: statuses,
            activeActionTitle: "Update \(secret)",
            lastActionNotice: "Finished \(secret)",
            errorDescription: "Service failed with \(secret)"
        )

        XCTAssertEqual(model.activeActionTitle, "Update [REDACTED]")
        XCTAssertEqual(model.lastActionNotice, "Finished [REDACTED]")
        XCTAssertEqual(model.errorMessage, "Service failed with [REDACTED]")
        XCTAssertEqual(model.updates.first?.title, "Old [REDACTED]")
        XCTAssertEqual(model.updates.first?.detail, "1.0-[REDACTED] -> 1.1-[REDACTED]")
        XCTAssertEqual(
            model.approvals.first?.detail,
            "update.cmd: [REDACTED] fresh update"
        )
        XCTAssertEqual(model.errors.first?.detail, "failed with [REDACTED]")
        XCTAssertFalse(String(describing: model).contains(secret))
    }

    func testFallbackTrackingCountsUniqueSectionItemIDs() {
        let duplicate = item(id: "shared", name: "Shared", status: .outdated)
        let repeated = item(id: "shared", name: "Shared", status: .error)
        let installed = item(id: "installed", name: "Installed", status: .ok)
        let state = state(
            outdatedItems: [duplicate],
            errorItems: [repeated],
            okItems: [installed]
        )

        let model = MenuBarPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: [:]
        )

        XCTAssertEqual(model.trackedItemCount, 2)
    }

    func testMissingApprovalStatusProducesDisabledRow() {
        let approval = item(id: "tool", name: "Tool", status: .untrusted)
        let state = state(approvalItems: [approval], allItems: [approval])

        let model = MenuBarPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: [:]
        )

        XCTAssertEqual(model.approvals.count, 1)
        XCTAssertEqual(model.approvals.first?.title, "Tool")
        XCTAssertEqual(model.approvals.first?.detail, "No command fields")
        XCTAssertEqual(model.approvals.first?.stateLabel, "Needs approval")
        XCTAssertNil(model.approvals.first?.action)
        XCTAssertNil(model.approvals.first?.confirmation)
    }

    private func state(
        outdatedItems: [StatusItem] = [],
        approvalItems: [StatusItem] = [],
        errorItems: [StatusItem] = [],
        okItems: [StatusItem] = [],
        allItems: [StatusItem] = []
    ) -> MenuBarState {
        MenuBarState(
            title: "Status",
            badgeValue: nil,
            outdatedItems: outdatedItems,
            approvalItems: approvalItems,
            errorItems: errorItems,
            okItems: okItems,
            allItems: allItems
        )
    }

    private func item(
        id: String,
        name: String,
        current: String? = nil,
        latest: String? = nil,
        status: ItemStatus,
        lastChecked: Date? = nil,
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
            lastChecked: lastChecked,
            error: error
        )
    }
}
