import Foundation
import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class StatusCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testStatusJSONMatchesMenuBarContractAndReturnsOutdatedExit() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        try saveManifest(
            home: home,
            items: [
                recipe(id: "zeta", name: "Zeta Tool"),
                recipe(id: "alpha", name: "Alpha Tool"),
            ])
        try StateStore(paths: AppPaths(homeDirectory: home)).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "zeta": ItemState(
                        current: "1.0.0",
                        latest: "1.1.0",
                        status: .outdated,
                        lastChecked: now,
                        error: nil,
                        backoffUntil: nil
                    ),
                    "alpha": ItemState(
                        current: "2.0.0",
                        latest: "2.0.0",
                        status: .ok,
                        lastChecked: now,
                        error: nil,
                        backoffUntil: nil
                    ),
                ]))

        let result = try CLIProcess.run(["status", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 10)
        XCTAssertTrue(result.stderr.isEmpty)
        let snapshot = try JSONDecoder.updateBar.decode(
            StatusSnapshot.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(snapshot.summary.total, 2)
        XCTAssertEqual(snapshot.summary.outdated, 1)
        XCTAssertEqual(snapshot.items.map(\.id), ["alpha", "zeta"])
    }

    func testStatusExitZeroOnOutdatedFlagReturnsSuccess() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        try saveManifest(home: home, items: [recipe(id: "tool", name: "Tool")])
        try StateStore(paths: AppPaths(homeDirectory: home)).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": ItemState(
                        current: "1.0.0",
                        latest: "1.1.0",
                        status: .outdated,
                        lastChecked: now,
                        error: nil,
                        backoffUntil: nil
                    )
                ]))

        let result = try CLIProcess.run(
            ["status", "--json", "--exit-zero-on-outdated"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let snapshot = try JSONDecoder.updateBar.decode(
            StatusSnapshot.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(snapshot.summary.outdated, 1)
    }

    func testStatusRefreshMarksItemsCheckingWithoutRunningCommands() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        try saveManifest(home: home, items: [recipe(id: "tool", name: "Tool")])

        let result = try CLIProcess.run(
            ["status", "--json", "--refresh", "--exit-zero-on-outdated"], home: home)
        let state = try StateStore(paths: AppPaths(homeDirectory: home)).load()

        XCTAssertEqual(result.exitCode, 0)
        let snapshot = try JSONDecoder.updateBar.decode(
            StatusSnapshot.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(snapshot.items.first?.status, .checking)
        XCTAssertEqual(state.items["tool"]?.status, .checking)
    }

    func testStatusRefreshUsesDefaultConfigWithoutCreatingConfigFile() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(home: home, items: [recipe(id: "tool", name: "Tool")])

        let result = try CLIProcess.run(
            ["status", "--json", "--refresh", "--exit-zero-on-outdated"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
    }

    func testStatusRefreshRejectsInvalidManifestWithoutCreatingState() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        let paths = AppPaths(homeDirectory: home)
        let secret = "sk-or-v1-secret-value"
        var item = recipe(id: "tool", name: "Tool")
        item.update.cmd = "tool update --token \(secret)"
        try saveManifest(home: home, items: [item])

        let result = try CLIProcess.run(
            ["status", "--json", "--refresh", "--exit-zero-on-outdated"], home: home)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorEnvelope.self, from: Data(result.stdout.utf8))
        let combined = result.stdout + result.stderr

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "registry_error")
        XCTAssertTrue(
            payload.errors.contains {
                $0.contains("items[0].update.cmd: must not contain literal secrets")
            })
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
        XCTAssertFalse(combined.contains(secret))
    }

    func testStatusRejectsInvalidManifestWithoutRefreshOrStateWrite() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        let paths = AppPaths(homeDirectory: home)
        let secret = "sk-or-v1-secret-value"
        var item = recipe(id: "tool", name: "Tool")
        item.update.cmd = "tool update --token \(secret)"
        try saveManifest(home: home, items: [item])

        let result = try CLIProcess.run(
            ["status", "--json", "--exit-zero-on-outdated"], home: home)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorEnvelope.self, from: Data(result.stdout.utf8))
        let combined = result.stdout + result.stderr

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "registry_error")
        XCTAssertTrue(
            payload.errors.contains {
                $0.contains("items[0].update.cmd: must not contain literal secrets")
            })
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
        XCTAssertFalse(combined.contains(secret))
    }

    func testStatusRefreshWithoutCheckableItemsDoesNotCreateStateFile() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        let paths = AppPaths(homeDirectory: home)
        var item = recipe(id: "tool", name: "Tool")
        item.trust.level = .untrusted
        item.trust.approvedCommands = [:]
        try saveManifest(home: home, items: [item])

        let result = try CLIProcess.run(
            ["status", "--json", "--refresh", "--exit-zero-on-outdated"], home: home)
        let snapshot = try JSONDecoder.updateBar.decode(
            StatusSnapshot.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(snapshot.items.first?.status, .untrusted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
    }

    func testStatusWithoutRefreshDoesNotCreateStateFile() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(home: home, items: [recipe(id: "tool", name: "Tool")])

        let result = try CLIProcess.run(
            ["status", "--json", "--exit-zero-on-outdated"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let snapshot = try JSONDecoder.updateBar.decode(
            StatusSnapshot.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(snapshot.items.first?.status, .checking)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
    }

    func testStatusHumanUntrustedPrintsReviewNextSteps() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        var item = recipe(id: "tool", name: "Tool")
        item.trust.level = .untrusted
        item.trust.approvedCommands = [:]
        try saveManifest(home: home, items: [item])

        let result = try CLIProcess.run(["status"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("tool\tuntrusted"))
        XCTAssertTrue(result.stdout.contains("updatebar approvals tool"))
        XCTAssertTrue(result.stdout.contains("updatebar check tool"))
        XCTAssertFalse(result.stdout.contains("updatebar approve tool"))
    }

    func testStatusHumanCheckingPrintsCheckNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        try saveManifest(home: home, items: [recipe(id: "tool", name: "Tool")])

        let result = try CLIProcess.run(["status"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("tool\tchecking"))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar check tool"))
    }

    func testStatusHumanOutputShowsUsefulItemDetails() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        try saveManifest(
            home: home,
            items: [
                recipe(id: "old", name: "Old Tool"),
                recipe(id: "broken", name: "Broken Tool"),
            ])
        try StateStore(paths: AppPaths(homeDirectory: home)).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "old": ItemState(
                        current: "1.0.0",
                        latest: "1.1.0",
                        status: .outdated,
                        lastChecked: now,
                        error: nil,
                        backoffUntil: nil
                    ),
                    "broken": ItemState(
                        current: "2.0.0",
                        latest: nil,
                        status: .error,
                        lastChecked: now,
                        error: "command failed",
                        backoffUntil: nil
                    ),
                ]))

        let result = try CLIProcess.run(["status"], home: home)

        XCTAssertEqual(result.exitCode, 10)
        XCTAssertTrue(result.stdout.contains("ID\tSTATUS\tCURRENT\tLATEST\tNAME\tDETAIL"))
        XCTAssertTrue(result.stdout.contains("old\toutdated\t1.0.0\t1.1.0\tOld Tool\t"))
        XCTAssertTrue(
            result.stdout.contains("broken\terror\t2.0.0\t-\tBroken Tool\tcommand failed"))
    }

    func testStatusHumanEmptyRegistryPrintsInitNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(["status"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("No items registered."))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar init"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
    }

    func testStatusRefreshEmptyRegistryDoesNotCreateRegistryFiles() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(
            ["status", "--json", "--refresh", "--exit-zero-on-outdated"], home: home)
        let snapshot = try JSONDecoder.updateBar.decode(
            StatusSnapshot.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(snapshot.summary.total, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
    }

    func testStatusWithoutRefreshDoesNotCreateMissingHomeDirectory() throws {
        let parent = try makeTemporaryHome(prefix: "updatebar-cli-status-tests")
        let home = parent.appendingPathComponent("missing-home")

        let result = try CLIProcess.run(
            ["status", "--json", "--exit-zero-on-outdated"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
    }

    private func saveManifest(home: URL, items: [Recipe]) throws {
        let manifest = Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
        try ManifestStore(paths: AppPaths(homeDirectory: home)).save(manifest)
    }

    private func recipe(id: String, name: String) -> Recipe {
        var item = Recipe(
            id: id,
            name: name,
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: id, branch: nil),
            versionScheme: .semver,
            check: .command("exit 42"),
            latest: LatestSpec(strategy: .cmd, cmd: "exit 43", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "exit 44", cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &item)
        return item
    }

    private struct ErrorEnvelope: Decodable {
        var code: String
        var errors: [String]
    }
}
