import XCTest
import UpdateBarCore

final class CLISmokeTests: XCTestCase {
    func testTargetIsDiscoverable() {
        XCTAssertTrue(true)
    }

    func testCLIProcessRunTimesOutHungCommand() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-process-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest())
        try StateStore(paths: paths).save(State(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_800),
            items: [
                "slow": ItemState(
                    current: "1.0.0",
                    latest: "1.1.0",
                    status: .outdated,
                    lastChecked: nil,
                    error: nil,
                    backoffUntil: nil
                )
            ]
        ))

        XCTAssertThrowsError(
            try CLIProcess.run(["update", "slow", "--yes"], home: home, timeout: 0.1)
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "CLI process timed out: update slow --yes"
            )
        }
    }

    private func manifest() -> Manifest {
        let now = Date(timeIntervalSince1970: 1_800)
        var recipe = Recipe(
            id: "slow",
            name: "Slow",
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: "slow", branch: nil),
            versionScheme: .semver,
            check: .command("printf 'slow 1.0.0'"),
            latest: LatestSpec(strategy: .cmd, cmd: "printf 'slow 1.1.0'", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "sleep 5", cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &recipe)
        return Manifest(
            schemaVersion: 1,
            items: [recipe],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
    }
}
