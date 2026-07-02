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

    func testCheckJSONStreamReportsCancellationWithFinishedSummary() throws {
        let home = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: home)
        var recipe = fixtureRecipe()
        recipe.check = .command("sleep 5")
        TrustPolicy.approveAllCommands(in: &recipe)
        try ManifestStore(paths: paths).save(manifest(items: [recipe]))

        let result = try CLIProcess.runAndInterrupt(
            ["check", "fixture-tool", "--json-stream"],
            home: home,
            after: 0.5
        )
        let events = try decodeEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(events.map(\.event), [.started, .itemStarted, .cancelled, .finished])
        XCTAssertEqual(events.count, 4)
        guard events.count == 4 else { return }
        XCTAssertEqual(events[2].checkSummary?.total, 0)
        XCTAssertEqual(events[3].checkSummary?.total, 0)
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

    func testCheckHumanEmptyRegistryPrintsInitNextStep() throws {
        let home = try temporaryDirectory()

        let result = try CLIProcess.run(["check"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("No items registered."))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar init"))
    }

    func testCheckHumanUntrustedPrintsApprovalNextSteps() throws {
        let home = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: home)
        var recipe = fixtureRecipe()
        recipe.trust.level = .untrusted
        recipe.trust.approvedCommands = [:]
        try ManifestStore(paths: paths).save(manifest(items: [recipe]))

        let result = try CLIProcess.run(["check", "fixture-tool"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("fixture-tool\tuntrusted"))
        XCTAssertTrue(result.stdout.contains("updatebar approvals fixture-tool"))
        XCTAssertFalse(result.stdout.contains("updatebar approve fixture-tool"))
    }

    func testCheckHumanOutdatedWithUnapprovedUpdatePrintsUpdateApprovalNextStep() throws {
        let home = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: home)
        var recipe = fixtureRecipe()
        TrustPolicy.approveAllCommands(in: &recipe)
        recipe.trust.approvedCommands.removeValue(forKey: "update.cmd")
        try ManifestStore(paths: paths).save(manifest(items: [recipe]))

        let result = try CLIProcess.run(["check", "fixture-tool"], home: home)

        XCTAssertEqual(result.exitCode, 10)
        XCTAssertTrue(result.stdout.contains("fixture-tool\toutdated"))
        XCTAssertTrue(result.stdout.contains("updatebar approvals fixture-tool"))
        XCTAssertFalse(result.stdout.contains("updatebar approve fixture-tool"))
    }

    func testCheckHumanApprovedOutdatedDoesNotPrintApprovalNextStep() throws {
        let home = try temporaryDirectory()
        try saveManifest(home: home)

        let result = try CLIProcess.run(["check", "fixture-tool"], home: home)

        XCTAssertEqual(result.exitCode, 10)
        XCTAssertTrue(result.stdout.contains("fixture-tool\toutdated"))
        XCTAssertFalse(result.stdout.contains("updatebar approvals fixture-tool"))
        XCTAssertFalse(result.stdout.contains("Next"))
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
        var recipe = fixtureRecipe()
        TrustPolicy.approveAllCommands(in: &recipe)
        try ManifestStore(paths: AppPaths(homeDirectory: home)).save(manifest(items: [recipe]))
    }

    private func fixtureRecipe() -> Recipe {
        Recipe(
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
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
    }

    private func manifest(items: [Recipe]) -> Manifest {
        let now = Date(timeIntervalSince1970: 1_800)
        return Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
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
