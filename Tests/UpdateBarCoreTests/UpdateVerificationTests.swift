import Foundation
import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class UpdateVerificationTests: XCTestCase {
    func testSuccessfulCommandDoesNotCountAnUnchangedInstalledVersionAsUpdated() throws {
        let fixture = try fixture()
        let result = try run(fixture, current: "1.0.0")

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(UpdateReport(results: [result]).summary.updated, 0)
    }

    func testSuccessfulCommandDoesNotCountAFailedLocalVersionCheckAsUpdated() throws {
        let fixture = try fixture()
        let result = try run(fixture, current: nil)

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertNil(try fixture.history.events().first?.to)
    }

    func testFailedCommandDoesNotRecordTheTargetAsAnObservedVersion() throws {
        let fixture = try fixture()
        _ = try run(fixture, current: "1.1.0", exitCode: 1)

        XCTAssertNil(try fixture.history.events().first?.to)
    }

    func testSuccessfulCommandDoesNotCountADowngradeAsUpdated() throws {
        let fixture = try fixture()
        let result = try run(fixture, current: "0.9.0")

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(try fixture.history.events().first?.to, "0.9.0")
    }

    func testFreshInstalledTargetCountsAsUpdatedWhenLatestLookupFails() throws {
        let fixture = try fixture()
        let result = try run(fixture, current: "1.1.0", latest: nil)

        XCTAssertEqual(result.outcome, .updated)
        XCTAssertEqual(result.current, "1.1.0")
    }

    func testFreshInstalledTargetCountsAsUpdatedWhenANewerRemoteVersionAppears() throws {
        let fixture = try fixture()
        let result = try run(fixture, current: "1.1.0", latest: "1.2.0")

        XCTAssertEqual(result.outcome, .updated)
        XCTAssertEqual(try fixture.history.events().first?.to, "1.1.0")
    }

    func testOpaqueVersionMustMatchThePlannedTarget() throws {
        let fixture = try fixture(scheme: .opaque)
        let result = try run(fixture, current: "1.2.0")

        XCTAssertEqual(result.outcome, .failed)
    }

    private struct Fixture {
        let paths: AppPaths
        let history: HistoryStore
    }

    private func fixture(scheme: VersionScheme = .semver) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-verification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let paths = AppPaths(homeDirectory: root)
        var recipe = Recipe(
            id: "tool", name: "Tool", category: "cli", path: nil,
            source: Source(kind: .custom, ref: "tool", branch: nil),
            versionScheme: scheme,
            check: .command("tool current"),
            latest: LatestSpec(strategy: .cmd, cmd: "tool latest", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "tool update", cwd: nil), pin: nil, enabled: true,
            trust: Trust(level: .untrusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &recipe)
        let now = Date(timeIntervalSince1970: 1_800)
        try ManifestStore(paths: paths).save(
            Manifest(
                schemaVersion: 1, items: [recipe],
                provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
            ))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": ItemState(
                        current: "1.0.0", latest: "1.1.0", status: .outdated,
                        lastChecked: now, error: nil, backoffUntil: nil
                    )
                ]
            ))
        return Fixture(paths: paths, history: HistoryStore(paths: paths))
    }

    private func run(
        _ fixture: Fixture, current: String?, latest: String? = "1.1.0", exitCode: Int32 = 0
    ) throws -> UpdateResult {
        let commands = MockCommandExecutor(results: [
            "tool update": CommandResult(exitCode: exitCode, stdout: "", stderr: "update failed"),
            "tool current": CommandResult(
                exitCode: current == nil ? 1 : 0, stdout: current ?? "",
                stderr: "current unavailable"
            ),
            "tool latest": CommandResult(
                exitCode: latest == nil ? 1 : 0, stdout: latest ?? "", stderr: "latest unavailable"
            ),
        ])
        let runner = UpdateRunner(
            manifestStore: ManifestStore(paths: fixture.paths),
            stateStore: StateStore(paths: fixture.paths), commandRunner: commands,
            now: { Date(timeIntervalSince1970: 1_800) }, historyStore: fixture.history
        )
        return try XCTUnwrap(runner.update(ids: ["tool"], all: false, assumeYes: true).first)
    }
}
