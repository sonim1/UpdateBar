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
}
