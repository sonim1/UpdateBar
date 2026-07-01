import Foundation
import XCTest
import UpdateBarCore

final class CheckCommandTests: XCTestCase {
    func testCheckJSONPrintsResultsOnlyAndReturnsOutdatedExit() throws {
        let home = try temporaryDirectory()
        try saveManifest(home: home)

        let result = try CLIProcess.run(["check", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 10)
        XCTAssertTrue(result.stderr.isEmpty)
        let results = try JSONDecoder.updateBar.decode([CheckResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "fixture-tool")
        XCTAssertEqual(results[0].status, .outdated)
    }

    func testCheckExitZeroOnOutdatedFlagReturnsSuccess() throws {
        let home = try temporaryDirectory()
        try saveManifest(home: home)

        let result = try CLIProcess.run(["check", "--json", "--exit-zero-on-outdated"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let results = try JSONDecoder.updateBar.decode([CheckResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results[0].status, .outdated)
    }

    func testCheckJSONStreamPrintsLineDelimitedEventsAndReturnsOutdatedExit() throws {
        let home = try temporaryDirectory()
        try saveManifest(home: home)

        let result = try CLIProcess.run(["check", "--json-stream"], home: home)
        let events = try decodeEvents(result.stdout)
        let rawEvents = try decodeRawEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 10)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(events.map(\.event), [.started, .itemStarted, .itemFinished, .finished])
        XCTAssertEqual(events.map(\.operation), [.check, .check, .check, .check])
        XCTAssertEqual(events[1].itemId, "fixture-tool")
        XCTAssertEqual(events[2].checkResult?.status, .outdated)
        XCTAssertEqual(events[3].checkSummary?.outdated, 1)
        XCTAssertEqual(
            rawEvents.compactMap { $0["type"] as? String },
            ["started", "item_started", "item_finished", "finished"]
        )
        XCTAssertEqual(Set(rawEvents.compactMap { $0["run_id"] as? String }).count, 1)
        XCTAssertTrue(rawEvents.allSatisfy { ($0["run_id"] as? String)?.isEmpty == false })
    }

    func testCheckJSONStreamExitZeroOnOutdatedFlagReturnsSuccess() throws {
        let home = try temporaryDirectory()
        try saveManifest(home: home)

        let result = try CLIProcess.run(
            ["check", "--json-stream", "--exit-zero-on-outdated"],
            home: home
        )
        let events = try decodeEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(events.last?.event, .finished)
        XCTAssertEqual(events.last?.checkSummary?.outdated, 1)
    }

    func testCheckWithJSONSpaceSeparatedFalseFallsBackToHumanMode() throws {
        let home = try temporaryDirectory()
        try saveManifest(home: home)

        let result = try CLIProcess.run(["check", "--json", "false"], home: home)

        XCTAssertEqual(result.exitCode, 10)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertTrue(result.stdout.contains("fixture-tool"))
        XCTAssertFalse(result.stdout.contains("\"id\""))
    }

    func testCheckRejectsJSONAndJSONStreamTogether() throws {
        let home = try temporaryDirectory()
        try saveManifest(home: home)

        let result = try CLIProcess.run(["check", "--json", "--json-stream"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.stdout.isEmpty)
        XCTAssertTrue(result.stdout.contains("usage_error"))
        XCTAssertTrue(result.stdout.contains("cannot be combined"))
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testCheckDeduplicatesIDs() throws {
        let home = try temporaryDirectory()
        try saveManifest(home: home)

        let result = try CLIProcess.run(["check", "fixture-tool", "fixture-tool", "--json"], home: home)
        let results = try JSONDecoder.updateBar.decode([CheckResult].self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "fixture-tool")
    }

    private func saveManifest(home: URL) throws {
        let now = Date(timeIntervalSince1970: 1_800)
        var recipe = Recipe(
            id: "fixture-tool",
            name: "Fixture Tool",
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: "fixture-tool", branch: nil),
            versionScheme: .semver,
            check: .command("printf 'fixture-tool 1.0.0'"),
            latest: LatestSpec(strategy: .cmd, cmd: "printf 'fixture-tool 1.1.0'", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "printf updated", cwd: nil),
            pin: nil,
            enabled: true,
            notify: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &recipe)
        let manifest = Manifest(
            schemaVersion: 1,
            items: [recipe],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
        try ManifestStore(paths: AppPaths(homeDirectory: home)).save(manifest)
    }

    private func temporaryDirectory() throws -> URL {
        try makeTemporaryHome(prefix: "updatebar-cli-check-tests")
    }

    private func decodeEvents(_ stdout: String) throws -> [MachineEvent] {
        try stdout.split(separator: "\n").map { line in
            try JSONDecoder.updateBar.decode(MachineEvent.self, from: Data(line.utf8))
        }
    }

    private func decodeRawEvents(_ stdout: String) throws -> [[String: Any]] {
        try stdout.split(separator: "\n").map { line in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try XCTUnwrap(object as? [String: Any])
        }
    }
}
