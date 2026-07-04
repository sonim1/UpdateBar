import Foundation
import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class ConcurrencyCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testOverlappingCommandsDoNotCorruptStoresOrLoseUnrelatedItems() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-concurrency-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [recipe(id: "anchor"), recipe(id: "tool")]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "anchor": itemState(),
                    "tool": itemState(),
                ]))

        let commands = [
            ["status", "--json", "--refresh", "--exit-zero-on-outdated"],
            ["approve", "tool", "--field", "update.cmd"],
            ["remove", "tool", "--yes"],
            ["check", "anchor", "--json", "--force", "--exit-zero-on-outdated"],
        ]
        let group = DispatchGroup()
        let results = ResultCollector()

        for index in 0..<24 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                if let result = try? CLIProcess.run(commands[index % commands.count], home: home) {
                    results.append(result)
                }
            }
        }

        group.wait()

        XCTAssertEqual(results.count, 24)
        let finalManifest = try ManifestStore(paths: paths).load()
        let finalState = try StateStore(paths: paths).load()
        XCTAssertNotNil(finalManifest.item(id: "anchor"))
        XCTAssertNotNil(finalState.items["anchor"])
    }

    private func manifest(items: [Recipe]) -> Manifest {
        Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
    }

    private func recipe(id: String) -> Recipe {
        var item = Recipe(
            id: id,
            name: id,
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: id, branch: nil),
            versionScheme: .semver,
            check: .command("printf '\(id) 1.0.0'"),
            latest: LatestSpec(strategy: .cmd, cmd: "printf '\(id) 1.1.0'", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "printf updated", cwd: nil),
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

    private final class ResultCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [CLIProcess.Result] = []

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage.count
        }

        func append(_ result: CLIProcess.Result) {
            lock.lock()
            storage.append(result)
            lock.unlock()
        }
    }
}
