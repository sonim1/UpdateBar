import Foundation
import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class CLIUpdateJobsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testUpdateAcceptsJobsOverride() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-jobs-tests")

        let result = try CLIProcess.run(["update", "--jobs", "2", "--yes", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[]")
    }

    func testUpdateRejectsJobsOutsideAllowedRange() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-jobs-tests")

        let result = try CLIProcess.run(["update", "--jobs", "0", "--yes"], home: home)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue((result.stdout + result.stderr).contains("--jobs must be between 1 and 8"))
    }

    func testUpdateJobsOverrideConfiguredConcurrency() throws {
        let serialHome = try configuredConcurrentUpdateHome()
        let serialStarted = Date()
        let serialResult = try CLIProcess.run(["update", "--yes", "--json"], home: serialHome)
        let serialElapsed = Date().timeIntervalSince(serialStarted)

        let parallelHome = try configuredConcurrentUpdateHome()
        let parallelStarted = Date()
        let parallelResult = try CLIProcess.run(
            ["update", "--jobs", "2", "--yes", "--json"],
            home: parallelHome
        )
        let parallelElapsed = Date().timeIntervalSince(parallelStarted)

        XCTAssertEqual(serialResult.exitCode, 0)
        XCTAssertEqual(parallelResult.exitCode, 0)
        for result in [serialResult, parallelResult] {
            let updates = try JSONDecoder.updateBar.decode(
                [UpdateResult].self, from: Data(result.stdout.utf8))
            XCTAssertEqual(updates.count, 2)
            XCTAssertTrue(updates.allSatisfy { $0.outcome == .updated && $0.current == "1.1.0" })
        }
        XCTAssertLessThan(
            parallelElapsed,
            serialElapsed - 0.2,
            "--jobs must override the configured serial update limit"
        )
    }

    private func configuredConcurrentUpdateHome() throws -> URL {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-jobs-tests")
        let paths = AppPaths(homeDirectory: home)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let firstVersion = home.appendingPathComponent("first-version")
        let secondVersion = home.appendingPathComponent("second-version")
        try "1.0.0".write(to: firstVersion, atomically: true, encoding: .utf8)
        try "1.0.0".write(to: secondVersion, atomically: true, encoding: .utf8)
        let firstScript = try writeSleeper(named: "slow-first", version: firstVersion, in: home)
        let secondScript = try writeSleeper(named: "slow-second", version: secondVersion, in: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(id: "first", version: firstVersion, updateCommand: firstScript),
                recipe(id: "second", version: secondVersion, updateCommand: secondScript),
            ])
        )
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1,
                generatedAt: now,
                items: [
                    "first": itemState(),
                    "second": itemState(),
                ]
            )
        )
        var config = Config.default
        config.update.maxConcurrent = 1
        try ConfigStore(paths: paths).save(config)
        return home
    }

    private func manifest(items: [Recipe]) -> Manifest {
        Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
    }

    private func recipe(id: String, version: URL, updateCommand: String) -> Recipe {
        var item = Recipe(
            id: id,
            name: id,
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: id, branch: nil),
            versionScheme: .semver,
            check: .command("cat \(ShellQuote.single(version.path))"),
            latest: LatestSpec(strategy: .cmd, cmd: "printf '\(id) 1.1.0'", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: updateCommand, cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &item)
        return item
    }

    private func itemState() -> ItemState {
        ItemState(
            current: "1.0.0",
            latest: "1.1.0",
            status: .outdated,
            lastChecked: now,
            error: nil,
            backoffUntil: nil
        )
    }

    private func writeSleeper(named name: String, version: URL, in home: URL) throws -> String {
        let script = home.appendingPathComponent(name)
        let content = "#!/bin/sh\nsleep 0.4\nprintf '1.1.0' > \(ShellQuote.single(version.path))\n"
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        return script.path
    }
}
