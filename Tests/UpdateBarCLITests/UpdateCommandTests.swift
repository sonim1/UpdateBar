import Foundation
import XCTest
import UpdateBarCore

final class UpdateCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testUpdateSelectedItemJSONRunsAndRefreshesState() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: [
            recipe(id: "tool", updateCommand: "printf updated", currentCommand: "printf 'tool 1.1.0'")
        ]))
        try StateStore(paths: paths).save(State(schemaVersion: 1, generatedAt: now, items: [
            "tool": itemState(status: .outdated)
        ]))

        let result = try CLIProcess.run(["update", "tool", "--yes", "--json"], home: home)
        let state = try StateStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        let results = try JSONDecoder.updateBar.decode([UpdateResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results.map(\.outcome), [.updated])
        XCTAssertEqual(state.items["tool"]?.status, .ok)
        XCTAssertEqual(state.items["tool"]?.current, "1.1.0")
    }

    func testUpdateAllReturnsPartialFailureExitCode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: [
            recipe(id: "bad", updateCommand: "printf 'sk-or-v1-secret' >&2; exit 3", currentCommand: "printf 'bad 1.0.0'"),
            recipe(id: "good", updateCommand: "printf updated", currentCommand: "printf 'good 1.1.0'")
        ]))
        try StateStore(paths: paths).save(State(schemaVersion: 1, generatedAt: now, items: [
            "bad": itemState(status: .outdated),
            "good": itemState(status: .outdated)
        ]))

        let result = try CLIProcess.run(["update", "--all", "--yes", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 2)
        let results = try JSONDecoder.updateBar.decode([UpdateResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results.map(\.outcome), [.failed, .updated])
        XCTAssertFalse(results[0].error?.contains("sk-or-v1-secret") ?? true)
    }

    func testUpdateBlockedOnApprovalReturnsDistinctExitCode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        var item = recipe(id: "tool", updateCommand: "printf updated", currentCommand: "printf 'tool 1.0.0'")
        item.trust.level = .untrusted
        item.trust.approvedCommands = [:]
        try ManifestStore(paths: paths).save(manifest(items: [item]))
        try StateStore(paths: paths).save(State(schemaVersion: 1, generatedAt: now, items: [
            "tool": itemState(status: .outdated)
        ]))

        let result = try CLIProcess.run(["update", "tool", "--yes", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 3)
        let results = try JSONDecoder.updateBar.decode([UpdateResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results.map(\.outcome), [.skippedUntrusted])
    }

    private func manifest(items: [Recipe]) -> Manifest {
        Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
    }

    private func recipe(id: String, updateCommand: String, currentCommand: String) -> Recipe {
        var item = Recipe(
            id: id,
            name: id,
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: id, branch: nil),
            versionScheme: .semver,
            check: .command(currentCommand),
            latest: LatestSpec(strategy: .cmd, cmd: "printf '\(id) 1.1.0'", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: updateCommand, cwd: nil),
            pin: nil,
            enabled: true,
            notify: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &item)
        return item
    }

    private func itemState(status: ItemStatus) -> ItemState {
        ItemState(
            current: "1.0.0",
            latest: "1.1.0",
            status: status,
            lastChecked: now,
            error: nil,
            backoffUntil: nil
        )
    }
}
