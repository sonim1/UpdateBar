import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class MenuBarActionCoordinatorTests: XCTestCase {
    func testRejectsSecondActionWhileOneIsActive() {
        let coordinator = MenuBarActionCoordinator()

        let first = coordinator.begin("Check Now")
        let second = coordinator.begin("Run Updates")

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(coordinator.activeAction?.title, "Check Now")
        XCTAssertEqual(coordinator.lastActionNotice, "Already running: Check Now")
        XCTAssertFalse(first?.token.isCancelled ?? true)
    }

    func testStopRequestsDrainWithoutCancellingTheRunningCommand() {
        let coordinator = MenuBarActionCoordinator()
        guard let action = coordinator.begin("Run Updates") else {
            XCTFail("expected action to start")
            return
        }

        XCTAssertNotNil(coordinator.stopActive())

        XCTAssertTrue(action.isStopRequested)
        XCTAssertTrue(action.stopSignal.isStopRequested)
        XCTAssertFalse(action.token.isCancelled, "stop must not kill the running command")
        XCTAssertEqual(coordinator.lastActionNotice, "Stopping after current: Run Updates")

        coordinator.finish(action, outcome: .finished)

        XCTAssertNil(coordinator.activeAction)
        XCTAssertEqual(coordinator.lastActionNotice, "Finished: Run Updates")
    }

    func testProgressTracksPlannedInFlightAndFinishedItems() {
        let coordinator = MenuBarActionCoordinator()
        guard let action = coordinator.begin("Run Updates") else {
            XCTFail("expected action to start")
            return
        }

        XCTAssertTrue(action.progress.isEmpty)

        action.apply(.planned([planItem(id: "alpha"), planItem(id: "bravo")]))
        XCTAssertEqual(action.progress.plannedIDs, ["alpha", "bravo"])
        XCTAssertEqual(action.progress.totalCount, 2)
        XCTAssertEqual(action.progress.completedCount, 0)

        action.apply(.itemStarted(id: "alpha", name: "alpha"))
        XCTAssertEqual(action.progress.inFlightIDs, ["alpha"])

        action.apply(.itemFinished(updateResult(id: "alpha")))
        XCTAssertEqual(action.progress.inFlightIDs, [])
        XCTAssertEqual(action.progress.finishedIDs, ["alpha"])
        XCTAssertEqual(action.progress.completedCount, 1)
    }

    private func planItem(id: String) -> UpdatePlanItem {
        UpdatePlanItem(
            id: id,
            name: id,
            decision: .willUpdate,
            current: "1.0.0",
            latest: "1.1.0",
            commandFingerprint: nil
        )
    }

    private func updateResult(id: String) -> UpdateResult {
        UpdateResult(
            id: id,
            name: id,
            outcome: .updated,
            current: "1.1.0",
            latest: "1.1.0",
            error: nil,
            commandFingerprint: nil
        )
    }
}
