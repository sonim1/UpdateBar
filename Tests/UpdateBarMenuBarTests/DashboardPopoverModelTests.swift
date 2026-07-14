import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class DashboardPopoverModelTests: XCTestCase {
    func testBuildsEmptyPresentationState() {
        let state = MenuBarState(
            title: "Up to date",
            badgeValue: nil,
            outdatedItems: [],
            approvalItems: [],
            errorItems: [],
            okItems: []
        )

        let model = DashboardPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: [:]
        )

        XCTAssertEqual(model.title, "Up to date")
        XCTAssertEqual(model.trackedItemCount, 0)
        XCTAssertEqual(model.updateCount, 0)
        XCTAssertEqual(model.approvalCount, 0)
        XCTAssertEqual(model.errorCount, 0)
        XCTAssertNil(model.lastChecked)
        XCTAssertNil(model.activeActionTitle)
        XCTAssertNil(model.lastActionNotice)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.updates, [])
        XCTAssertEqual(model.approvals, [])
        XCTAssertEqual(model.errors, [])
    }

    func testMapsSummaryAndReadOnlyRows() {
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let latest = Date(timeIntervalSince1970: 1_700_000_100)
        let update = item(
            id: "old",
            name: "Old Tool",
            current: "1.0.0",
            latest: "1.1.0",
            status: .outdated,
            lastChecked: earlier
        )
        let approval = item(
            id: "approval",
            name: "Approval Tool",
            status: .untrusted,
            lastChecked: latest
        )
        let missing = item(id: "missing", name: "Missing Tool", status: .untrusted)
        let error = item(
            id: "broken",
            name: "Broken Tool",
            status: .error,
            error: "command failed"
        )
        let state = MenuBarState(
            title: "1 update",
            badgeValue: "1",
            outdatedItems: [update],
            approvalItems: [approval, missing],
            errorItems: [error],
            okItems: [],
            allItems: [update, approval, missing, error]
        )
        let statuses = [
            "approval": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: true,
                    fingerprint: "approved",
                    command: "tool update",
                    cwd: nil
                ),
                CommandApprovalStatus(
                    field: "check.cmd",
                    approved: false,
                    fingerprint: "pending",
                    command: "tool check",
                    cwd: nil
                ),
            ]
        ]

        let model = DashboardPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: statuses
        )

        XCTAssertEqual(model.title, "1 update")
        XCTAssertEqual(model.trackedItemCount, 4)
        XCTAssertEqual(model.updateCount, 1)
        XCTAssertEqual(model.approvalCount, 2)
        XCTAssertEqual(model.errorCount, 1)
        XCTAssertEqual(model.lastChecked, latest)
        XCTAssertEqual(
            model.updates,
            [
                DashboardPopoverRow(
                    id: "update-old",
                    title: "Old Tool",
                    detail: "1.0.0 -> 1.1.0",
                    stateLabel: "Ready"
                )
            ]
        )
        XCTAssertEqual(
            model.approvals,
            [
                DashboardPopoverRow(
                    id: "approval-approval-update.cmd",
                    title: "Approval Tool",
                    detail: "update.cmd: tool update",
                    stateLabel: "Approved"
                ),
                DashboardPopoverRow(
                    id: "approval-approval-check.cmd",
                    title: "Approval Tool",
                    detail: "check.cmd: tool check",
                    stateLabel: "Needs approval"
                ),
                DashboardPopoverRow(
                    id: "approval-missing",
                    title: "Missing Tool",
                    detail: "No command fields",
                    stateLabel: "Needs approval"
                ),
            ]
        )
        XCTAssertEqual(
            model.errors,
            [
                DashboardPopoverRow(
                    id: "error-broken",
                    title: "Broken Tool",
                    detail: "command failed",
                    stateLabel: "Error"
                )
            ]
        )
    }

    func testRedactsSensitiveRowsAndPresentationState() {
        let secret = "sk-or-v1-secret-value"
        let approval = item(id: "approval", name: "Approval Tool", status: .untrusted)
        let error = item(
            id: "broken",
            name: "Broken Tool",
            status: .error,
            error: "failed with \(secret)"
        )
        let state = MenuBarState(
            title: "Needs attention",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: [approval],
            errorItems: [error],
            okItems: [],
            allItems: [approval, error]
        )
        let statuses = [
            "approval": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: false,
                    fingerprint: "pending",
                    command: "OPENROUTER_API_KEY=\(secret) tool update",
                    cwd: nil
                )
            ]
        ]

        let model = DashboardPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: statuses,
            activeActionTitle: "Update \(secret)",
            lastActionNotice: "Finished \(secret)",
            errorDescription: "service failed with OPENROUTER_API_KEY=\(secret)"
        )

        XCTAssertEqual(model.activeActionTitle, "Update [REDACTED]")
        XCTAssertEqual(model.lastActionNotice, "Finished [REDACTED]")
        XCTAssertEqual(model.errorMessage, "service failed with [REDACTED]")
        XCTAssertEqual(model.approvals.first?.detail, "update.cmd: [REDACTED] tool update")
        XCTAssertEqual(model.errors.first?.detail, "failed with [REDACTED]")
        XCTAssertFalse(model.approvals.first?.detail.contains(secret) ?? true)
        XCTAssertFalse(model.errors.first?.detail.contains(secret) ?? true)
    }

    func testDeduplicatesFallbackItemsWhenAllItemsIsEmpty() {
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let latest = Date(timeIntervalSince1970: 1_700_000_200)
        let shared = item(
            id: "shared",
            name: "Shared Tool",
            current: "1.0.0",
            latest: "1.1.0",
            status: .outdated,
            lastChecked: earlier
        )
        let duplicate = item(
            id: "shared",
            name: "Shared Tool",
            status: .untrusted,
            lastChecked: latest
        )
        let other = item(id: "other", name: "Other Tool", status: .ok)
        let state = MenuBarState(
            title: "1 update",
            badgeValue: "1",
            outdatedItems: [shared],
            approvalItems: [duplicate],
            errorItems: [],
            okItems: [other],
            allItems: []
        )

        let model = DashboardPopoverModelBuilder().makeModel(
            state: state,
            approvalStatuses: [:]
        )

        XCTAssertEqual(model.trackedItemCount, 2)
        XCTAssertEqual(model.lastChecked, latest)
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
