import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class UpdateRunnerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testPlannerSelectsOnlyOutdatedApprovedItemsForUpdate() throws {
        let ready = recipe(id: "ready")
        var pinned = recipe(id: "pinned")
        pinned.pin = "1.0.0"
        var disabled = recipe(id: "disabled")
        disabled.enabled = false
        var untrusted = recipe(id: "untrusted")
        untrusted.trust.level = .untrusted
        untrusted.trust.approvedCommands = [:]

        let planner = UpdatePlanner(
            manifest: manifest(items: [ready, pinned, disabled, untrusted, recipe(id: "ok")]),
            state: State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "ready": itemState(status: .outdated),
                    "pinned": itemState(status: .outdated),
                    "disabled": itemState(status: .outdated),
                    "untrusted": itemState(status: .outdated),
                    "ok": itemState(status: .ok),
                ])
        )

        let plan = planner.plan(ids: [], all: true)

        XCTAssertEqual(plan.map(\.id), ["ready", "pinned", "disabled", "untrusted", "ok"])
        XCTAssertEqual(
            plan.map(\.decision),
            [.willUpdate, .skippedPinned, .skippedDisabled, .skippedUntrusted, .skippedNotOutdated]
        )
    }

    func testRunnerUpdatesItemAndChecksItAfterSuccess() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool")]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))
        let commands = MockCommandExecutor(results: [
            "tool update": CommandResult(exitCode: 0, stdout: "updated", stderr: ""),
            "tool current": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
            "tool latest": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
        ])
        let runner = updateRunner(paths: paths, commands: commands)

        let results = try runner.update(ids: ["tool"], all: false, assumeYes: true)
        let state = try StateStore(paths: paths).load()

        XCTAssertEqual(results.map(\.outcome), [.updated])
        XCTAssertEqual(
            commands.commands.map(\.command), ["tool update", "tool current", "tool latest"])
        XCTAssertEqual(state.items["tool"]?.status, .ok)
        XCTAssertEqual(state.items["tool"]?.current, "1.1.0")
    }

    func testRunnerExpandsTildeInUpdateWorkingDirectoryUsingHomeEnvironment() throws {
        let userHome = try temporaryDirectory()

        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        var item = recipe(id: "tool")
        item.update.cwd = "~/workspace"
        TestApprovals.approveAllCommands(in: &item)
        try ManifestStore(paths: paths).save(manifest(items: [item]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))
        let commands = MockCommandExecutor(results: [
            "tool update": CommandResult(exitCode: 0, stdout: "updated", stderr: ""),
            "tool current": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
            "tool latest": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
        ])
        let runner = updateRunner(
            paths: paths, commands: commands, environment: ["HOME": userHome.path])

        _ = try runner.update(ids: ["tool"], all: false, assumeYes: true)

        XCTAssertEqual(
            commands.commands.first?.cwd, userHome.appendingPathComponent("workspace").path)
    }

    func testRunnerReturnsPartialFailureAndRedactsErrors() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try ManifestStore(paths: paths).save(
            manifest(items: [recipe(id: "bad"), recipe(id: "good")]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "bad": itemState(status: .outdated),
                    "good": itemState(status: .outdated),
                ]))
        let githubToken = "ghp_1234567890abcdefghijklmnopqrstuvwxyz"
        let commands = MockCommandExecutor(results: [
            "bad update": CommandResult(
                exitCode: 1, stdout: "", stderr: "failed sk-or-v1-secret \(githubToken)"),
            "good update": CommandResult(exitCode: 0, stdout: "updated", stderr: ""),
            "good current": CommandResult(exitCode: 0, stdout: "good 1.1.0", stderr: ""),
            "good latest": CommandResult(exitCode: 0, stdout: "good 1.1.0", stderr: ""),
        ])
        let runner = updateRunner(paths: paths, commands: commands)

        let results = try runner.update(ids: [], all: true, assumeYes: true)

        XCTAssertEqual(results.map(\.id), ["bad", "good"])
        XCTAssertEqual(results.map(\.outcome), [.failed, .updated])
        XCTAssertFalse(results[0].error?.contains("sk-or-v1-secret") ?? true)
        XCTAssertFalse(results[0].error?.contains(githubToken) ?? true)
        let state = try StateStore(paths: paths).load()
        XCTAssertFalse(state.items["bad"]?.error?.contains("sk-or-v1-secret") ?? true)
        XCTAssertFalse(state.items["bad"]?.error?.contains(githubToken) ?? true)
    }

    func testRunnerRejectsInvalidManifestBeforeExecutingUpdateCommands() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        var item = recipe(id: "bad")
        item.update.cmd = "OPENROUTER_API_KEY=sk-or-v1-secret-value bad update"
        TestApprovals.approveAllCommands(in: &item)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                item
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "bad": itemState(status: .outdated)
                ]))
        let commands = MockCommandExecutor(results: [:])
        let runner = updateRunner(paths: paths, commands: commands)

        XCTAssertThrowsError(try runner.update(ids: ["bad"], all: false, assumeYes: true)) {
            error in
            guard case RegistryError.invalidManifest(let errors) = error else {
                return XCTFail("expected invalid manifest, got \(error)")
            }
            XCTAssertTrue(errors.contains("items[0].update.cmd: must not contain literal secrets"))
        }
        XCTAssertTrue(commands.commands.isEmpty)
    }

    func testRunnerSkipsPinnedDisabledUntrustedAndNotOutdatedItemsWithoutCommands() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        var pinned = recipe(id: "pinned")
        pinned.pin = "1.0.0"
        var disabled = recipe(id: "disabled")
        disabled.enabled = false
        var untrusted = recipe(id: "untrusted")
        untrusted.trust.level = .untrusted
        untrusted.trust.approvedCommands = [:]
        try ManifestStore(paths: paths).save(
            manifest(items: [pinned, disabled, untrusted, recipe(id: "ok")]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "pinned": itemState(status: .outdated),
                    "disabled": itemState(status: .outdated),
                    "untrusted": itemState(status: .outdated),
                    "ok": itemState(status: .ok),
                ]))
        let commands = MockCommandExecutor(results: [:])
        let runner = updateRunner(paths: paths, commands: commands)

        let results = try runner.update(ids: [], all: true, assumeYes: true)

        XCTAssertEqual(
            results.map(\.outcome),
            [.skippedPinned, .skippedDisabled, .skippedUntrusted, .skippedNotOutdated]
        )
        XCTAssertTrue(commands.commands.isEmpty)
    }

    func testRunnerPlansFromStores() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool")]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))
        let runner = updateRunner(paths: paths, commands: MockCommandExecutor(results: [:]))

        let plan = try runner.plan(ids: ["tool"], all: false)

        XCTAssertEqual(plan.map(\.id), ["tool"])
        XCTAssertEqual(plan.map(\.decision), [.willUpdate])
    }

    func testUpdateReportSummarizesResults() throws {
        let results = [
            updateResult(id: "updated", outcome: .updated),
            updateResult(id: "failed", outcome: .failed),
            updateResult(id: "pinned", outcome: .skippedPinned),
            updateResult(id: "untrusted", outcome: .skippedUntrusted),
            updateResult(id: "missing", outcome: .missing),
            updateResult(id: "cancelled", outcome: .cancelled),
        ]

        let report = UpdateReport(results: results)

        XCTAssertEqual(report.summary.total, 6)
        XCTAssertEqual(report.summary.updated, 1)
        XCTAssertEqual(report.summary.failed, 1)
        XCTAssertEqual(report.summary.skipped, 2)
        XCTAssertEqual(report.summary.skippedUntrusted, 1)
        XCTAssertEqual(report.summary.missing, 1)
        XCTAssertEqual(report.summary.cancelled, 1)
        XCTAssertEqual(report.summary.hardFailures, 3)
        XCTAssertTrue(UpdateOutcome.failed.isHardFailure)
        XCTAssertFalse(UpdateOutcome.skippedUntrusted.isHardFailure)
    }

    func testUpdateResultRedactsLegacyMetadataSecrets() {
        let secret = "sk-or-v1-update-secret-value"

        let result = UpdateResult(
            id: secret,
            name: "Tool \(secret)",
            outcome: .updated,
            current: "1.0.0",
            latest: "1.1.0",
            error: nil,
            commandFingerprint: nil
        )

        XCTAssertEqual(result.id, "[REDACTED]")
        XCTAssertEqual(result.name, "Tool [REDACTED]")
        XCTAssertFalse(String(describing: result).contains(secret))
    }

    private func updateRunner(
        paths: AppPaths,
        commands: MockCommandExecutor,
        environment: [String: String] = [:]
    ) -> UpdateRunner {
        UpdateRunner(
            manifestStore: ManifestStore(paths: paths),
            stateStore: StateStore(paths: paths),
            config: Config.default,
            httpClient: MockHTTPClient(responses: [:]),
            commandRunner: commands,
            now: { self.now },
            environment: environment,
            confirm: { _ in true }
        )
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
            check: .command("\(id) current"),
            latest: LatestSpec(strategy: .cmd, cmd: "\(id) latest", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "\(id) update", cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &item)
        return item
    }

    private func itemState(status: ItemStatus) -> ItemState {
        ItemState(
            current: status == .ok ? "1.1.0" : "1.0.0",
            latest: "1.1.0",
            status: status,
            lastChecked: now,
            error: nil,
            backoffUntil: nil
        )
    }

    private func updateResult(id: String, outcome: UpdateOutcome) -> UpdateResult {
        UpdateResult(
            id: id,
            name: id,
            outcome: outcome,
            current: nil,
            latest: nil,
            error: nil,
            commandFingerprint: nil
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-update-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
