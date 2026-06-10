import Foundation
import XCTest
import UpdateBarCore

final class ListCommandTests: XCTestCase {
    func testListJSONReturnsManifestItemsWithoutStateMutation() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-list-tests")
        let paths = AppPaths(homeDirectory: home)
        let now = Date(timeIntervalSince1970: 1_800)
        let manifest = Manifest(
            schemaVersion: 1,
            items: [
                recipe(id: "bravo", name: "Bravo Tool"),
                recipe(id: "alpha", name: "Alpha Tool")
            ],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
        try ManifestStore(paths: paths).save(manifest)

        let result = try CLIProcess.run(["list", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
        let items = try JSONDecoder.updateBar.decode([Recipe].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(items.map(\.id), ["alpha", "bravo"])
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
            notify: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &item)
        return item
    }
}
