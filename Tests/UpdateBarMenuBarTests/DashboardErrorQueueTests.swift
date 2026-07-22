import UpdateBarMenuBar
import XCTest

final class DashboardErrorQueueTests: XCTestCase {
    func testSecondMessageWaitsUntilFirstPresentationFinishes() throws {
        var queue = DashboardErrorQueue()
        queue.enqueue("first")

        let first = try XCTUnwrap(queue.beginNextPresentation())
        queue.enqueue("second")

        XCTAssertEqual(first.message, "first")
        XCTAssertTrue(queue.hasActivePresentation)
        XCTAssertEqual(queue.queuedMessageCount, 1)
        XCTAssertNil(queue.beginNextPresentation())

        XCTAssertTrue(queue.finishPresentation(token: first.token))
        let second = try XCTUnwrap(queue.beginNextPresentation())
        XCTAssertEqual(second.message, "second")
        XCTAssertEqual(queue.queuedMessageCount, 0)
    }

    func testClearDropsQueuedMessagesAndRejectsStaleCompletion() throws {
        var queue = DashboardErrorQueue()
        queue.enqueue("first")
        queue.enqueue("second")
        let first = try XCTUnwrap(queue.beginNextPresentation())

        queue.clear()

        XCTAssertFalse(queue.hasActivePresentation)
        XCTAssertEqual(queue.queuedMessageCount, 0)
        XCTAssertFalse(queue.finishPresentation(token: first.token))
        XCTAssertNil(queue.beginNextPresentation())
    }
}
