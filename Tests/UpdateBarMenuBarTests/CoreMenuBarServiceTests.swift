import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import UpdateBarTestSupport
import XCTest

final class CoreMenuBarServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testCoreServiceScansTheUserHomeInsteadOfTheUpdateBarDataDirectory() throws {
        let root = try temporaryDirectory()
        let dataDirectory = root.appendingPathComponent("data", isDirectory: true)
        let userHome = root.appendingPathComponent("user", isDirectory: true)
        let skillDirectory =
            userHome
            .appendingPathComponent(".codex/skills/live-sync", isDirectory: true)
        try FileManager.default.createDirectory(
            at: skillDirectory,
            withIntermediateDirectories: true
        )
        try Data("# Live Sync\n".utf8).write(
            to: skillDirectory.appendingPathComponent("SKILL.md")
        )
        let service = CoreMenuBarService(
            paths: AppPaths(homeDirectory: dataDirectory),
            scanHomeDirectory: userHome,
            now: { self.now }
        )

        let report = try service.scan(category: "codex-skill")

        XCTAssertEqual(report.candidates.map(\.id), ["codex_skill.live-sync"])
        XCTAssertEqual(report.candidates.first?.sourceRef, "~/.codex/skills/live-sync")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataDirectory.path))
    }

    func testCoreServiceScansRegistersSelectedCandidatesAndSavesConfig() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let commands = MockCommandExecutor(results: [
            ScanService.brewListCommand: CommandResult(
                exitCode: 0,
                stdout: "jq 1.7.1\n",
                stderr: ""
            ),
            ScanService.npmGlobalListCommand: CommandResult(
                exitCode: 0,
                stdout: #"{"dependencies":{}}"#,
                stderr: ""
            ),
            ScanService.knownToolsCommand: CommandResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let service = CoreMenuBarService(paths: paths, commandRunner: commands, now: { self.now })

        let report = try service.scan(category: "shell-utility")
        let summary = try service.registerScannedCandidates(
            report.candidates,
            selectedIDs: ["brew.jq"],
            replace: false
        )
        var config = try service.loadConfig()
        config.refresh.interval = Duration(minutes: 30)
        config.security.requireHTTPSSource = false
        try service.saveConfig(config)

        XCTAssertEqual(report.candidates.map(\.id), ["brew.jq"])
        XCTAssertEqual(summary.added, ["brew.jq"])
        let manifest = try ManifestStore(paths: paths).load()
        let recipe = try XCTUnwrap(manifest.item(id: "brew.jq"))
        XCTAssertTrue(recipe.enabled)
        XCTAssertEqual(recipe.trust.level, .untrusted)
        XCTAssertEqual(recipe.trust.approvedCommands, [:])
        let savedConfig = try ConfigStore(paths: paths).load()
        XCTAssertEqual(savedConfig.refresh.interval, Duration(minutes: 30))
        XCTAssertFalse(savedConfig.security.requireHTTPSSource)
    }

    func testCoreServiceReadsStatusApprovalsAndRunsUpdate() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(id: "tool", updateCommand: "tool update", currentCommand: "tool current")
            ]))
        try StateStore(paths: paths).save(
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
        let commands = RecordingCommandRunner(results: [
            "tool update": CommandResult(exitCode: 0, stdout: "updated", stderr: ""),
            "tool current": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
            "tool latest": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
        ])
        let service = CoreMenuBarService(paths: paths, commandRunner: commands, now: { self.now })

        let status = try service.status(refresh: false)
        let approvals = try service.approvals(id: "tool")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
        try service.update(id: "tool")
        let state = try StateStore(paths: paths).load()

        XCTAssertEqual(status.summary.outdated, 1)
        XCTAssertEqual(approvals.map(\.field), ["check.cmd", "latest.cmd", "update.cmd"])
        XCTAssertTrue(approvals.allSatisfy(\.approved))
        XCTAssertEqual(
            commands.commands.map(\.command), ["tool update", "tool current", "tool latest"])
        XCTAssertEqual(state.items["tool"]?.status, .ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
    }

    func testCoreServiceCancelsLongRunningUpdateCommand() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(id: "slow", updateCommand: "sleep 5", currentCommand: "slow current")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "slow": ItemState(
                        current: "1.0.0",
                        latest: "1.1.0",
                        status: .outdated,
                        lastChecked: now,
                        error: nil,
                        backoffUntil: nil
                    )
                ]))
        let service = CoreMenuBarService(paths: paths, now: { self.now })
        let token = CancellationToken()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            token.cancel()
        }

        try service.update(id: "slow", cancellationToken: token)
        let state = try StateStore(paths: paths).load()

        XCTAssertTrue(token.isCancelled)
        XCTAssertNotEqual(state.items["slow"]?.status, .ok)
    }

    func testCoreServiceKeepsInjectedCommandRunnerWhenCancellationTokenIsProvided() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(id: "tool", updateCommand: "tool update", currentCommand: "tool current")
            ]))
        try StateStore(paths: paths).save(
            State(schemaVersion: 1, generatedAt: now, items: [:]))
        let commands = RecordingCommandRunner(results: [
            "tool current": CommandResult(exitCode: 0, stdout: "tool 1.0.0", stderr: ""),
            "tool latest": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
        ])
        let service = CoreMenuBarService(
            paths: paths,
            commandRunner: commands,
            now: { self.now })
        let token = CancellationToken()

        try service.checkNow(cancellationToken: token)
        let state = try StateStore(paths: paths).load()

        XCTAssertEqual(
            commands.commands.map(\.command),
            ["tool current", "tool latest"])
        XCTAssertEqual(state.items["tool"]?.status, .outdated)
    }

    func testCoreServicePreservesScannedItemAcrossDisableAndReenable() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let candidateRecipe = recipe(
            id: "tool", updateCommand: "tool update", currentCommand: "tool current")
        let candidate = ScanCandidate(
            id: candidateRecipe.id,
            name: candidateRecipe.name,
            detector: .known,
            category: candidateRecipe.category,
            capability: .full,
            confidence: .high,
            installedVersion: "1.0.0",
            sourceRef: candidateRecipe.source.ref,
            recipe: candidateRecipe
        )
        let service = CoreMenuBarService(paths: paths, now: { self.now })

        let summary = try service.registerScannedCandidates(
            [candidate], selectedIDs: [candidate.id], replace: false)
        let registered = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: candidate.id))

        XCTAssertEqual(summary.added, [candidate.id])
        XCTAssertEqual(registered.trust.level, .untrusted)
        XCTAssertEqual(registered.trust.approvedCommands, [:])

        for field in ["check.cmd", "latest.cmd", "update.cmd"] {
            try service.approve(id: candidate.id, field: field)
        }
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1,
                generatedAt: now,
                items: [
                    candidate.id: ItemState(
                        current: "1.0.0",
                        latest: "1.1.0",
                        status: .outdated,
                        lastChecked: now,
                        error: nil,
                        backoffUntil: nil
                    )
                ]
            ))
        try HistoryStore(paths: paths).append(
            HistoryEvent(event: .checkFinished, outdated: 1, at: now))
        let approved = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: candidate.id))
        let stateBeforeToggle = try StateStore(paths: paths).load()
        let historyBeforeToggle = try service.history(since: nil)
        let manifestCreatedAt = try ManifestStore(paths: paths).load().provenance.createdAt

        try service.setEnabled(id: candidate.id, enabled: false)
        let disabledManifest = try ManifestStore(paths: paths).load()
        let disabledRecipe = try XCTUnwrap(disabledManifest.item(id: candidate.id))
        var expectedDisabledRecipe = approved
        expectedDisabledRecipe.enabled = false
        let disabled = try service.status(refresh: false)

        XCTAssertEqual(disabledManifest.items.count, 1)
        XCTAssertEqual(disabledManifest.provenance.createdAt, manifestCreatedAt)
        XCTAssertEqual(disabledRecipe, expectedDisabledRecipe)
        XCTAssertEqual(disabledRecipe.trust, approved.trust)
        XCTAssertEqual(try StateStore(paths: paths).load(), stateBeforeToggle)
        XCTAssertEqual(try service.history(since: nil), historyBeforeToggle)
        XCTAssertEqual(disabled.items.first?.status, .disabled)

        try service.setEnabled(id: candidate.id, enabled: true)
        let reenabledManifest = try ManifestStore(paths: paths).load()
        let reenabledRecipe = try XCTUnwrap(reenabledManifest.item(id: candidate.id))
        let enabled = try service.status(refresh: false)

        XCTAssertEqual(reenabledManifest.items.map(\.id), [candidate.id])
        XCTAssertEqual(reenabledManifest.provenance.createdAt, manifestCreatedAt)
        XCTAssertEqual(reenabledRecipe, approved)
        XCTAssertEqual(try StateStore(paths: paths).load(), stateBeforeToggle)
        XCTAssertEqual(try service.history(since: nil), historyBeforeToggle)
        XCTAssertEqual(enabled.items.first?.status, .outdated)
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
            latest: LatestSpec(strategy: .cmd, cmd: "\(id) latest", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: updateCommand, cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &item)
        return item
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-core-menubar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class RecordingCommandRunner: CommandRunning {
    var results: [String: CommandResult]
    private(set) var commands: [ShellCommand] = []

    init(results: [String: CommandResult]) {
        self.results = results
    }

    func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult {
        commands.append(command)
        guard let result = results[command.command] else {
            throw MissingCommandError(command.command)
        }
        return result
    }
}

private struct MissingCommandError: Error {
    var command: String

    init(_ command: String) {
        self.command = command
    }
}
