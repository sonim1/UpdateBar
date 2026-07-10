import Foundation
import UpdateBarCore
import XCTest

final class HistoryStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testAppendsAndReadsEventsInOrder() throws {
        let store = try makeStore()

        try store.append(
            HistoryEvent(
                event: .updateFinished,
                id: "tool",
                from: "1.0.0",
                to: "1.1.0",
                outcome: "updated",
                at: now
            ))
        try store.append(
            HistoryEvent(event: .checkFinished, outdated: 2, at: now.addingTimeInterval(60)))

        let events = try store.events()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].event, .updateFinished)
        XCTAssertEqual(events[0].schemaVersion, 1)
        XCTAssertEqual(events[0].id, "tool")
        XCTAssertEqual(events[0].from, "1.0.0")
        XCTAssertEqual(events[0].to, "1.1.0")
        XCTAssertEqual(events[0].outcome, "updated")
        XCTAssertEqual(events[1].event, .checkFinished)
        XCTAssertEqual(events[1].outdated, 2)
    }

    func testSinceFiltersOlderEvents() throws {
        let store = try makeStore()
        try store.append(HistoryEvent(event: .checkFinished, outdated: 0, at: now))
        try store.append(
            HistoryEvent(event: .checkFinished, outdated: 1, at: now.addingTimeInterval(3_600)))

        let events = try store.events(since: now.addingTimeInterval(1_800))

        XCTAssertEqual(events.map(\.outdated), [1])
    }

    func testMissingFileReadsAsEmpty() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.events(), [])
    }

    func testRotationDropsOldestWholeLinesPastByteCap() throws {
        let paths = try temporaryPaths()
        let store = HistoryStore(paths: paths, maxBytes: 400)

        for index in 0..<20 {
            try store.append(
                HistoryEvent(
                    event: .updateFinished,
                    id: "tool-\(index)",
                    outcome: "updated",
                    at: now.addingTimeInterval(TimeInterval(index))
                ))
        }

        let size = try Data(contentsOf: paths.historyFile).count
        XCTAssertLessThanOrEqual(size, 400)
        let events = try store.events()
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.last?.id, "tool-19")
        XCTAssertNotEqual(events.first?.id, "tool-0")
    }

    func testSkipsMalformedLines() throws {
        let paths = try temporaryPaths()
        let store = HistoryStore(paths: paths)
        try store.append(HistoryEvent(event: .checkFinished, outdated: 3, at: now))
        let handle = try FileHandle(forWritingTo: paths.historyFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not-json\n".utf8))
        try handle.close()
        try store.append(HistoryEvent(event: .checkFinished, outdated: 4, at: now))

        XCTAssertEqual(try store.events().map(\.outdated), [3, 4])
    }

    func testRedactsSecretLikeValues() throws {
        let store = try makeStore()
        try store.append(
            HistoryEvent(
                event: .updateFinished,
                id: "tool-sk-or-v1-secret-value",
                outcome: "updated",
                at: now
            ))

        let events = try store.events()
        XCTAssertEqual(events.first?.id.map { $0.contains("[REDACTED]") }, true)
        XCTAssertEqual(events.first?.id.map { $0.contains("sk-or-v1-secret-value") }, false)
    }

    private func makeStore() throws -> HistoryStore {
        HistoryStore(paths: try temporaryPaths())
    }

    private func temporaryPaths() throws -> AppPaths {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-history-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return AppPaths(homeDirectory: url)
    }
}
