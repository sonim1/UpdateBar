import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class MenuBarStatusFormatterTests: XCTestCase {
    func testBuildsBadgeAndSeparatesUpdatesFromApprovalNeeds() throws {
        let snapshot = try decodeSnapshot(
            """
            {
              "generated_at": "2026-06-10T00:00:00Z",
              "summary": { "total": 4, "outdated": 1, "errors": 1 },
              "items": [
                { "id": "old", "name": "Old Tool", "category": "cli", "current": "1.0.0", "latest": "1.1.0", "status": "outdated", "pinned": false },
                { "id": "needs-approval", "name": "Needs Approval", "category": "cli", "status": "untrusted", "pinned": false },
                { "id": "broken", "name": "Broken Tool", "category": "cli", "current": "1.0.0", "status": "error", "pinned": false, "error": "command failed" },
                { "id": "fresh", "name": "Fresh Tool", "category": "cli", "current": "2.0.0", "latest": "2.0.0", "status": "ok", "pinned": false }
              ]
            }
            """
        )

        let state = MenuBarStatusFormatter().makeState(from: snapshot)

        XCTAssertEqual(state.badgeValue, "1")
        XCTAssertEqual(state.title, "1 update")
        XCTAssertEqual(state.outdatedItems.map(\.id), ["old"])
        XCTAssertEqual(state.approvalItems.map(\.id), ["needs-approval"])
        XCTAssertEqual(state.errorItems.map(\.id), ["broken"])
        XCTAssertEqual(state.okItems.map(\.id), ["fresh"])
        XCTAssertEqual(state.needsAttentionCount, 2)
    }

    func testEmptySnapshotUsesNeutralTitleAndNoBadge() throws {
        let snapshot = try decodeSnapshot(
            """
            {
              "generated_at": "2026-06-10T00:00:00Z",
              "summary": { "total": 0, "outdated": 0, "errors": 0 },
              "items": []
            }
            """
        )

        let state = MenuBarStatusFormatter().makeState(from: snapshot)

        XCTAssertNil(state.badgeValue)
        XCTAssertEqual(state.title, "Up to date")
        XCTAssertEqual(state.needsAttentionCount, 0)
    }

    func testAttentionSummaryUsesSingularAndPluralCopy() {
        let single = MenuBarState(
            title: "Needs attention",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: [
                StatusItem(
                    id: "one",
                    name: "One",
                    category: "cli",
                    current: nil,
                    latest: nil,
                    status: .untrusted,
                    pinned: false,
                    lastChecked: nil,
                    error: nil)
            ],
            errorItems: [],
            okItems: []
        )
        let plural = MenuBarState(
            title: "Needs attention",
            badgeValue: "!",
            outdatedItems: [],
            approvalItems: single.approvalItems,
            errorItems: [
                StatusItem(
                    id: "two",
                    name: "Two",
                    category: "cli",
                    current: nil,
                    latest: nil,
                    status: .error,
                    pinned: false,
                    lastChecked: nil,
                    error: nil)
            ],
            okItems: []
        )

        XCTAssertEqual(single.needsAttentionSummary, "1 needs attention")
        XCTAssertEqual(plural.needsAttentionSummary, "2 need attention")
    }

    func testAttentionOnlySnapshotDoesNotLookUpToDate() throws {
        let snapshot = try decodeSnapshot(
            """
            {
              "generated_at": "2026-06-10T00:00:00Z",
              "summary": { "total": 2, "outdated": 0, "errors": 1 },
              "items": [
                { "id": "needs-approval", "name": "Needs Approval", "category": "cli", "status": "untrusted", "pinned": false },
                { "id": "broken", "name": "Broken Tool", "category": "cli", "status": "error", "pinned": false, "error": "command failed" }
              ]
            }
            """
        )

        let state = MenuBarStatusFormatter().makeState(from: snapshot)

        XCTAssertEqual(state.title, "Needs attention")
        XCTAssertEqual(state.badgeValue, "!")
        XCTAssertEqual(state.needsAttentionCount, 2)
    }

    func testApprovalStatusesRecomputeAttentionBadgeWhenSnapshotLooksFresh() throws {
        let snapshot = try decodeSnapshot(
            """
            {
              "generated_at": "2026-06-10T00:00:00Z",
              "summary": { "total": 1, "outdated": 0, "errors": 0 },
              "items": [
                { "id": "fresh", "name": "Fresh Tool", "category": "cli", "current": "2.0.0", "latest": "2.0.0", "status": "ok", "pinned": false }
              ]
            }
            """
        )
        let approvals = [
            "fresh": [
                CommandApprovalStatus(
                    field: "update.cmd",
                    approved: false,
                    fingerprint: "abc",
                    command: "fresh update",
                    cwd: nil)
            ]
        ]

        let state = MenuBarStatusFormatter().makeState(
            from: snapshot,
            approvalsByItemID: approvals)

        XCTAssertEqual(state.title, "Needs attention")
        XCTAssertEqual(state.badgeValue, "!")
        XCTAssertEqual(state.approvalItems.map(\.id), ["fresh"])
        XCTAssertEqual(state.okItems.map(\.id), [])
        XCTAssertEqual(state.needsAttentionCount, 1)
    }

    private func decodeSnapshot(_ json: String) throws -> StatusSnapshot {
        try JSONDecoder.updateBar.decode(StatusSnapshot.self, from: Data(json.utf8))
    }
}
