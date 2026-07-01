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

    func testCancelAndFinishUpdateActionState() {
        let coordinator = MenuBarActionCoordinator()
        guard let action = coordinator.begin("Run Updates") else {
            XCTFail("expected action to start")
            return
        }

        XCTAssertNotNil(coordinator.cancelActive())
        XCTAssertTrue(action.token.isCancelled)
        XCTAssertEqual(coordinator.lastActionNotice, "Cancelling: Run Updates")

        coordinator.finish(action, outcome: .cancelled)

        XCTAssertNil(coordinator.activeAction)
        XCTAssertEqual(coordinator.lastActionNotice, "Cancelled: Run Updates")
    }
}
