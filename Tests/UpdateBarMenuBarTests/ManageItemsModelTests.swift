import UpdateBarCore
import XCTest

@testable import UpdateBarMenuBar

final class ManageItemsModelTests: XCTestCase {
    func testGroupsItemsByCategorySortedWithCounts() {
        let rows = ManageItemsModel().rows(from: [
            item(id: "b", name: "Beta", category: "cli", status: .ok),
            item(id: "a", name: "Alpha", category: "ai-agent", status: .outdated),
            item(id: "c", name: "Gamma", category: "cli", status: .disabled),
        ])

        XCTAssertEqual(
            rows,
            [
                .category(name: "ai-agent", count: 1),
                .item(
                    ManageItemRow(
                        id: "a",
                        name: "Alpha",
                        category: "ai-agent",
                        currentVersion: "1.0.0",
                        latestVersion: "1.1.0",
                        statusLabel: "outdated",
                        isEnabled: true
                    )),
                .category(name: "cli", count: 2),
                .item(
                    ManageItemRow(
                        id: "b",
                        name: "Beta",
                        category: "cli",
                        currentVersion: "1.0.0",
                        latestVersion: "1.1.0",
                        statusLabel: "up to date",
                        isEnabled: true
                    )),
                .item(
                    ManageItemRow(
                        id: "c",
                        name: "Gamma",
                        category: "cli",
                        currentVersion: "1.0.0",
                        latestVersion: "1.1.0",
                        statusLabel: "disabled",
                        isEnabled: false
                    )),
            ]
        )
    }

    func testEmptyCategoryFallsBackToUncategorized() {
        let rows = ManageItemsModel().rows(from: [
            item(id: "x", name: "X Tool", category: "", status: .ok)
        ])

        XCTAssertEqual(rows.first, .category(name: "uncategorized", count: 1))
    }

    func testDisabledItemsStayListedSoTheyCanBeReenabled() {
        let rows = ManageItemsModel().rows(from: [
            item(id: "off", name: "Off Tool", category: "cli", status: .disabled)
        ])

        guard case .item(let row)? = rows.last else {
            return XCTFail("expected item row")
        }
        XCTAssertFalse(row.isEnabled)
        XCTAssertEqual(row.statusLabel, "disabled")
    }

    func testErrorStatusIncludesMessage() {
        let rows = ManageItemsModel().rows(from: [
            item(
                id: "e",
                name: "Err Tool",
                category: "cli",
                status: .error,
                error: "check.cmd exited 1"
            )
        ])

        guard case .item(let row)? = rows.last else {
            return XCTFail("expected item row")
        }
        XCTAssertEqual(row.statusLabel, "error: check.cmd exited 1")
    }

    private func item(
        id: String,
        name: String,
        category: String,
        status: ItemStatus,
        error: String? = nil
    ) -> StatusItem {
        StatusItem(
            id: id,
            name: name,
            category: category,
            current: "1.0.0",
            latest: "1.1.0",
            status: status,
            pinned: false,
            lastChecked: nil,
            error: error
        )
    }
}

final class ManageItemsMutationGateTests: XCTestCase {
    func testExposesPendingItemForRowLocalProgress() {
        var gate = ManageItemsMutationGate()
        gate.begin(id: "tool", enabled: false)

        XCTAssertTrue(gate.isPending(id: "tool"))
        XCTAssertFalse(gate.isPending(id: "other"))

        gate.cancel()
        XCTAssertFalse(gate.isPending(id: "tool"))
    }

    func testRejectsStaleSnapshotUntilToggledStateAppears() {
        var gate = ManageItemsMutationGate()
        gate.begin(id: "tool", enabled: true)

        XCTAssertFalse(gate.accepts([item(status: .disabled)]))
        XCTAssertTrue(gate.isPending)
        XCTAssertTrue(gate.accepts([item(status: .ok)]))
        XCTAssertFalse(gate.isPending)
    }

    func testCancelAllowsSnapshotsAfterMutationFailure() {
        var gate = ManageItemsMutationGate()
        gate.begin(id: "tool", enabled: false)
        gate.cancel()

        XCTAssertTrue(gate.accepts([item(status: .ok)]))
        XCTAssertFalse(gate.isPending)
    }

    private func item(status: ItemStatus) -> StatusItem {
        StatusItem(
            id: "tool",
            name: "Tool",
            category: "cli",
            current: nil,
            latest: nil,
            status: status,
            pinned: false,
            lastChecked: nil,
            error: nil
        )
    }
}
