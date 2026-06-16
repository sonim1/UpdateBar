import XCTest
import UpdateBarCore

final class StateStoreTests: XCTestCase {
    func testStateStoreInitializesEmptyState() throws {
        let root = try temporaryDirectory()
        let store = StateStore(paths: AppPaths(homeDirectory: root))

        let state = try store.load(now: Date(timeIntervalSince1970: 1_812_499_200))

        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("state.json").path))
    }

    func testStateStoreWritesAndReadsPrivateFile() throws {
        let root = try temporaryDirectory()
        let store = StateStore(paths: AppPaths(homeDirectory: root))
        let now = Date(timeIntervalSince1970: 1_812_499_200)
        let state = State(
            schemaVersion: 1,
            generatedAt: now,
            items: [
                "claude-code": ItemState(
                    current: "1.4.2",
                    latest: "1.5.0",
                    status: .outdated,
                    lastChecked: now,
                    error: nil,
                    backoffUntil: nil
                )
            ]
        )

        try store.save(state)
        let loaded = try store.load(now: now)

        XCTAssertEqual(loaded, state)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("state.json").path
        )
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testStateStoreOverwritesExistingFile() throws {
        let root = try temporaryDirectory()
        let store = StateStore(paths: AppPaths(homeDirectory: root))
        let now = Date(timeIntervalSince1970: 1_812_499_200)
        let first = State(schemaVersion: 1, generatedAt: now, items: [:])
        let second = State(
            schemaVersion: 1,
            generatedAt: now.addingTimeInterval(60),
            items: [
                "tool": ItemState(
                    current: "1.0.0",
                    latest: "1.1.0",
                    status: .outdated,
                    lastChecked: now,
                    error: nil,
                    backoffUntil: nil
                )
            ]
        )

        try store.save(first)
        try store.save(second)

        XCTAssertEqual(try store.load(now: now), second)
    }

    func testStateStoreProvidesCrossProcessLockFileForReadModifyWrite() throws {
        let root = try temporaryDirectory()
        let store = StateStore(paths: AppPaths(homeDirectory: root))
        let state = State(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_800),
            items: [:]
        )

        try store.withExclusiveLock {
            try store.save(state)
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("state.lock").path)
        )
        XCTAssertEqual(try store.load(), state)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
