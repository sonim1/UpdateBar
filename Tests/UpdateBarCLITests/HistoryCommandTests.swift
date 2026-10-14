import Foundation
import UpdateBarCore
import XCTest

final class HistoryCommandTests: XCTestCase {
    func testJSONReadsLegacyAndDiagnosticHistoryTogether() throws {
        let home = try home()
        let paths = AppPaths(homeDirectory: home)
        let legacy = Data(
            #"{"schema_version":1,"event":"update_finished","id":"old","from":"1.0.0","to":"1.1.0","outcome":"updated","at":"2026-10-01T00:00:00Z"}"#
                .utf8
        )
        try legacy.write(to: paths.historyFile)
        let handle = try FileHandle(forWritingTo: paths.historyFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        try HistoryStore(paths: paths).append(
            HistoryEvent(
                event: .updateFinished, id: "new", from: "1.0.0", outcome: "failed",
                target: "1.1.0", error: "version unavailable", commandExitCode: 0,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            ))

        let result = try CLIProcess.run(["history", "--json"], home: home)
        let events = try JSONDecoder.updateBar.decode(
            [HistoryEvent].self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(events.map(\.id), ["old", "new"])
        XCTAssertNil(events[0].error)
        XCTAssertNil(events[1].to)
        XCTAssertEqual(events[1].target, "1.1.0")
        XCTAssertEqual(events[1].commandExitCode, 0)
    }

    func testHumanHistoryPreservesFailureReasonWithoutCreatingExtraRowsOrTerminalControls() throws {
        let home = try home()
        try HistoryStore(paths: AppPaths(homeDirectory: home)).append(
            HistoryEvent(
                event: .updateFinished, id: "tool", from: "1.0.0", outcome: "failed",
                target: "1.1.0", error: "network\nunavailable\t\u{1B}[31m", commandExitCode: 0,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            ))

        let result = try CLIProcess.run(["history"], home: home)
        let lines = result.stdout.split(separator: "\n")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1].split(separator: "\t").count, 4)
        XCTAssertTrue(result.stdout.contains("network"))
        XCTAssertTrue(result.stdout.contains("unavailable"))
        XCTAssertTrue(result.stdout.contains("target 1.1.0"))
        XCTAssertTrue(result.stdout.contains("command exit 0"))
        XCTAssertTrue(result.stdout.contains("installed version unverified"))
        XCTAssertFalse(result.stdout.contains("1.0.0 -> 1.1.0"))
        XCTAssertFalse(result.stdout.contains("\u{1B}"))
    }

    private func home() throws -> URL {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-history-tests")
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        return home
    }
}
