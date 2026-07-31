import Foundation
import XCTest

@testable import UpdateBarCore

final class UpdateSchedulerTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private(set) var peak = 0
        private(set) var laneOverlaps: [String] = []
        private var busyLanes: [String: Int] = [:]

        func enter(lane: String) {
            lock.lock()
            running += 1
            peak = max(peak, running)
            let count = (busyLanes[lane] ?? 0) + 1
            busyLanes[lane] = count
            if count > 1 { laneOverlaps.append(lane) }
            lock.unlock()
        }

        func leave(lane: String) {
            lock.lock()
            running -= 1
            busyLanes[lane] = (busyLanes[lane] ?? 1) - 1
            lock.unlock()
        }
    }

    private func items(_ lanes: [String]) -> [UpdateScheduler<String, String>.Item] {
        lanes.enumerated().map { .init(index: $0.offset, lane: $0.element, payload: $0.element) }
    }

    func testRunsEveryItemAndKeysResultsByIndex() throws {
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { "done-\($0)" }
        )

        let outputs = try scheduler.run(maxConcurrent: 3)

        XCTAssertEqual(outputs, [0: "done-a", 1: "done-b", 2: "done-c"])
    }

    func testDeliversStartAndFinishCallbacksSerially() throws {
        var log: [String] = []
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c"]),
            stopSignal: nil,
            // No lock here on purpose: the scheduler must serialise these.
            onStart: { log.append("start-\($0)") },
            onFinish: { log.append("finish-\($0)") },
            shouldStopAfter: nil,
            work: { $0 }
        )

        _ = try scheduler.run(maxConcurrent: 3)

        XCTAssertEqual(log.count, 6)
        XCTAssertEqual(log.filter { $0.hasPrefix("start-") }.count, 3)
        XCTAssertEqual(log.filter { $0.hasPrefix("finish-") }.count, 3)
    }

    func testNeverExceedsMaxConcurrent() throws {
        let recorder = Recorder()
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c", "d", "e", "f"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { lane in
                recorder.enter(lane: lane)
                Thread.sleep(forTimeInterval: 0.05)
                recorder.leave(lane: lane)
                return lane
            }
        )

        _ = try scheduler.run(maxConcurrent: 2)

        XCTAssertLessThanOrEqual(recorder.peak, 2)
        XCTAssertGreaterThan(recorder.peak, 1, "expected actual parallelism")
    }

    func testSameLaneItemsNeverOverlap() throws {
        let recorder = Recorder()
        let scheduler = UpdateScheduler<String, String>(
            items: items(["brew", "brew", "brew", "npm"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { lane in
                recorder.enter(lane: lane)
                Thread.sleep(forTimeInterval: 0.05)
                recorder.leave(lane: lane)
                return lane
            }
        )

        let outputs = try scheduler.run(maxConcurrent: 3)

        XCTAssertEqual(outputs.count, 4)
        XCTAssertEqual(recorder.laneOverlaps, [])
    }

    func testStopSignalPreventsNewItemsFromStarting() throws {
        let stopSignal = UpdateStopSignal()
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c", "d"]),
            stopSignal: stopSignal,
            onStart: { _ in stopSignal.requestStop() },
            onFinish: nil,
            shouldStopAfter: nil,
            work: { $0 }
        )

        let outputs = try scheduler.run(maxConcurrent: 1)

        XCTAssertEqual(outputs, [0: "a"], "items after the stop request must not run")
    }

    func testShouldStopAfterDrainsRemainingItems() throws {
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: { $0 == "a" },
            work: { $0 }
        )

        let outputs = try scheduler.run(maxConcurrent: 1)

        XCTAssertEqual(outputs, [0: "a"])
    }

    func testRethrowsWorkError() {
        struct Boom: Error {}
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { _ in throw Boom() }
        )

        XCTAssertThrowsError(try scheduler.run(maxConcurrent: 2)) { error in
            XCTAssertTrue(error is Boom)
        }
    }

    func testRethrowsFinishCallbackError() {
        struct Boom: Error {}
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: { _ in throw Boom() },
            shouldStopAfter: nil,
            work: { $0 }
        )

        XCTAssertThrowsError(try scheduler.run(maxConcurrent: 1)) { error in
            XCTAssertTrue(error is Boom)
        }
    }

    func testEmptyItemListReturnsEmpty() throws {
        let scheduler = UpdateScheduler<String, String>(
            items: [],
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { $0 }
        )

        XCTAssertEqual(try scheduler.run(maxConcurrent: 3), [:])
    }
}
