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

    func testProgressSkipsInFlightForItemsThatStartAndFinishInTheSameEvent() {
        // UpdateRunner's Phase 1 (classification) emits itemStarted
        // immediately followed by itemFinished for skipped/pinned/disabled
        // items -- no dwell time in flight. The menu must never show these
        // as "updating" even for an instant.
        let coordinator = MenuBarActionCoordinator()
        guard let action = coordinator.begin("Run Updates") else {
            XCTFail("expected action to start")
            return
        }

        action.apply(.planned([planItem(id: "skipped")]))
        action.apply(.itemStarted(id: "skipped", name: "skipped"))
        action.apply(.itemFinished(updateResult(id: "skipped")))

        XCTAssertEqual(action.progress.finishedIDs, ["skipped"])
        XCTAssertFalse(action.progress.inFlightIDs.contains("skipped"))
        XCTAssertTrue(action.progress.inFlightIDs.isEmpty)
    }

    func testProgressCountsOnlyItemsThatWillUpdate() {
        // UpdatePlanner returns every manifest item, so a registry with 3
        // outdated tools out of 50 must not open the menu at "(47/50)".
        let coordinator = MenuBarActionCoordinator()
        guard let action = coordinator.begin("Run Updates") else {
            XCTFail("expected action to start")
            return
        }

        action.apply(
            .planned([
                planItem(id: "alpha"),
                planItem(id: "current", decision: .skippedNotOutdated),
                planItem(id: "pinned", decision: .skippedPinned),
            ]))

        XCTAssertEqual(action.progress.plannedIDs, ["alpha"])
        XCTAssertEqual(action.progress.totalCount, 1)
        XCTAssertEqual(action.progress.completedCount, 0)

        // Phase 1 still emits start/finish for the skipped items; they must
        // not move the counter or light up as "updating".
        action.apply(.itemStarted(id: "current", name: "current"))
        action.apply(.itemFinished(updateResult(id: "current", outcome: .skippedNotOutdated)))
        action.apply(.itemStarted(id: "pinned", name: "pinned"))
        action.apply(.itemFinished(updateResult(id: "pinned", outcome: .skippedPinned)))

        XCTAssertEqual(action.progress.completedCount, 0)
        XCTAssertTrue(action.progress.inFlightIDs.isEmpty)
        XCTAssertTrue(action.progress.finishedIDs.isEmpty)

        action.apply(.itemStarted(id: "alpha", name: "alpha"))
        action.apply(.itemFinished(updateResult(id: "alpha")))

        XCTAssertEqual(action.progress.completedCount, 1)
        XCTAssertEqual(action.progress.totalCount, 1)
    }

    private func planItem(id: String, decision: UpdatePlanDecision = .willUpdate) -> UpdatePlanItem
    {
        UpdatePlanItem(
            id: id,
            name: id,
            decision: decision,
            current: "1.0.0",
            latest: "1.1.0",
            commandFingerprint: nil
        )
    }

    private func updateResult(id: String, outcome: UpdateOutcome = .updated) -> UpdateResult {
        UpdateResult(
            id: id,
            name: id,
            outcome: outcome,
            current: "1.1.0",
            latest: "1.1.0",
            error: nil,
            commandFingerprint: nil
        )
    }
}
