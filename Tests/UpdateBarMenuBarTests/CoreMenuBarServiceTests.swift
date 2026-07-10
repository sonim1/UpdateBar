import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import UpdateBarTestSupport
import XCTest

final class CoreMenuBarServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

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

    func testCoreServiceTogglesItemEnabledState() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(id: "tool", updateCommand: "tool update", currentCommand: "tool current")
            ]))
        try StateStore(paths: paths).save(
            State(schemaVersion: 1, generatedAt: now, items: [:]))
        let service = CoreMenuBarService(paths: paths, now: { self.now })

        try service.setEnabled(id: "tool", enabled: false)
        let disabled = try service.status(refresh: false)
        XCTAssertEqual(disabled.items.first?.status, .disabled)

        try service.setEnabled(id: "tool", enabled: true)
        let enabled = try service.status(refresh: false)
        XCTAssertNotEqual(enabled.items.first?.status, .disabled)
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
