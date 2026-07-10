import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class RegistryServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testCheckUpdatesStateForOneSelectedItem() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        try stores.manifest.save(
            manifest(items: [
                recipe(
                    id: "tool-one", currentCommand: "tool-one current",
                    latestCommand: "tool-one latest"),
                recipe(
                    id: "tool-two", currentCommand: "tool-two current",
                    latestCommand: "tool-two latest"),
            ]))
        let commands = MockCommandExecutor(results: [
            "tool-one current": CommandResult(exitCode: 0, stdout: "tool 1.0.0", stderr: ""),
            "tool-one latest": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
            "tool-two current": CommandResult(exitCode: 0, stdout: "tool 2.0.0", stderr: ""),
            "tool-two latest": CommandResult(exitCode: 0, stdout: "tool 2.1.0", stderr: ""),
        ])
        let service = registryService(paths: paths, commands: commands)

        let results = try service.check(ids: ["tool-one"], force: false)
        let state = try stores.state.load()

        XCTAssertEqual(results.map(\.id), ["tool-one"])
        XCTAssertEqual(results.first?.status, .outdated)
        XCTAssertEqual(state.items["tool-one"]?.current, "1.0.0")
        XCTAssertEqual(state.items["tool-one"]?.latest, "1.1.0")
        XCTAssertNil(state.items["tool-two"])
        XCTAssertEqual(commands.commands.map(\.command), ["tool-one current", "tool-one latest"])
    }

    func testCheckUpdatesAllEnabledTrustedItems() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        try stores.manifest.save(
            manifest(items: [
                recipe(id: "alpha", currentCommand: "alpha current", latestCommand: "alpha latest"),
                recipe(id: "beta", currentCommand: "beta current", latestCommand: "beta latest"),
            ]))
        let commands = MockCommandExecutor(results: [
            "alpha current": CommandResult(exitCode: 0, stdout: "alpha 1.0.0", stderr: ""),
            "alpha latest": CommandResult(exitCode: 0, stdout: "alpha 1.0.0", stderr: ""),
            "beta current": CommandResult(exitCode: 0, stdout: "beta 1.0.0", stderr: ""),
            "beta latest": CommandResult(exitCode: 0, stdout: "beta 1.2.0", stderr: ""),
        ])
        let service = registryService(paths: paths, commands: commands)

        let results = try service.check()

        XCTAssertEqual(results.map(\.id), ["alpha", "beta"])
        XCTAssertEqual(results.map(\.status), [.ok, .outdated])
        XCTAssertEqual(commands.commands.count, 4)
    }

    func testCheckSkipsDisabledItemsWithoutRunningCommands() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        var disabled = recipe(
            id: "disabled", currentCommand: "disabled current", latestCommand: "disabled latest")
        disabled.enabled = false
        try stores.manifest.save(manifest(items: [disabled]))
        let commands = MockCommandExecutor(results: [:])
        let service = registryService(paths: paths, commands: commands)

        let results = try service.check()
        let state = try stores.state.load()

        XCTAssertEqual(results.first?.status, .disabled)
        XCTAssertEqual(state.items["disabled"]?.status, .disabled)
        XCTAssertTrue(commands.commands.isEmpty)
    }

    func testCheckMarksPinnedItemsWithoutRunningCommands() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        var pinned = recipe(
            id: "pinned", currentCommand: "pinned current", latestCommand: "pinned latest")
        pinned.pin = "1.0.0"
        try stores.manifest.save(manifest(items: [pinned]))
        let commands = MockCommandExecutor(results: [:])
        let service = registryService(paths: paths, commands: commands)

        let results = try service.check()
        let state = try stores.state.load()

        XCTAssertEqual(results.first?.status, .pinned)
        XCTAssertEqual(state.items["pinned"]?.status, .pinned)
        XCTAssertTrue(commands.commands.isEmpty)
    }

    func testCheckReturnsItemErrorWithoutFailingOtherItems() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        try stores.manifest.save(
            manifest(items: [
                recipe(
                    id: "broken", currentCommand: "broken current", latestCommand: "broken latest"),
                recipe(id: "good", currentCommand: "good current", latestCommand: "good latest"),
            ]))
        let githubToken = "ghp_1234567890abcdefghijklmnopqrstuvwxyz"
        let commands = MockCommandExecutor(results: [
            "broken current": CommandResult(
                exitCode: 7, stdout: "", stderr: "boom sk-or-v1-secret \(githubToken)"),
            "good current": CommandResult(exitCode: 0, stdout: "good 1.0.0", stderr: ""),
            "good latest": CommandResult(exitCode: 0, stdout: "good 1.0.0", stderr: ""),
        ])
        let service = registryService(paths: paths, commands: commands)

        let results = try service.check()
        let state = try stores.state.load()

        XCTAssertEqual(results.map(\.id), ["broken", "good"])
        XCTAssertEqual(results.map(\.status), [.error, .ok])
        XCTAssertEqual(state.items["broken"]?.status, .error)
        XCTAssertEqual(state.items["good"]?.status, .ok)
        XCTAssertFalse(results[0].error?.contains("sk-or-v1-secret") ?? true)
        XCTAssertFalse(results[0].error?.contains(githubToken) ?? true)
        XCTAssertFalse(state.items["broken"]?.error?.contains("sk-or-v1-secret") ?? true)
        XCTAssertFalse(state.items["broken"]?.error?.contains(githubToken) ?? true)
    }

    func testCheckReportsMissingCheckFileWithReadableError() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        var item = recipe(
            id: "file-tool", currentCommand: "unused", latestCommand: "file-tool latest")
        let missingPath = root.appendingPathComponent("missing-version.txt").path
        item.check = .file(path: missingPath)
        TestApprovals.approveAllCommands(in: &item)
        try stores.manifest.save(manifest(items: [item]))
        let commands = MockCommandExecutor(results: [
            "file-tool latest": CommandResult(exitCode: 0, stdout: "file-tool 1.1.0", stderr: "")
        ])
        let service = registryService(paths: paths, commands: commands)

        let results = try service.check()
        let state = try stores.state.load()
        let error = try XCTUnwrap(results.first?.error)

        XCTAssertEqual(results.first?.status, .error)
        XCTAssertEqual(state.items["file-tool"]?.status, .error)
        XCTAssertTrue(error.contains("check.file not readable"))
        XCTAssertTrue(error.contains(missingPath))
        XCTAssertFalse(error.contains("Error Domain"))
        XCTAssertFalse(error.contains("NSCocoaErrorDomain"))
    }

    func testFileCheckExpandsTildeUsingHomeEnvironment() throws {
        let userHome = try temporaryDirectory()

        let versionFile = userHome.appendingPathComponent(".tool-version")
        try "tool 1.2.3\n".write(to: versionFile, atomically: true, encoding: .utf8)

        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        var item = recipe(
            id: "tool", currentCommand: "unused current", latestCommand: "tool latest")
        item.check = .file(path: "~/.tool-version")
        TestApprovals.approveAllCommands(in: &item)
        try stores.manifest.save(manifest(items: [item]))
        let commands = MockCommandExecutor(results: [
            "tool latest": CommandResult(exitCode: 0, stdout: "tool 1.2.3", stderr: "")
        ])
        let service = registryService(
            paths: paths, commands: commands, environment: ["HOME": userHome.path])

        let results = try service.check()

        XCTAssertEqual(results.first?.current, "1.2.3")
        XCTAssertEqual(results.first?.status, .ok)
    }

    func testCheckReportsVersionParseFailureWithReadableError() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        try stores.manifest.save(
            manifest(items: [
                recipe(
                    id: "parse-tool", currentCommand: "parse-tool current",
                    latestCommand: "parse-tool latest")
            ]))
        let commands = MockCommandExecutor(results: [
            "parse-tool current": CommandResult(exitCode: 0, stdout: "no version here", stderr: "")
        ])
        let service = registryService(paths: paths, commands: commands)

        let results = try service.check()
        let error = try XCTUnwrap(results.first?.error)

        XCTAssertEqual(results.first?.status, .error)
        XCTAssertTrue(error.contains("version_parse.regex did not match"))
        XCTAssertFalse(error.contains("missingMatch"))
    }

    func testCheckKeepsObservedCurrentVersionWhenLatestFails() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        try stores.manifest.save(
            manifest(items: [
                recipe(
                    id: "partial-tool", currentCommand: "partial-tool current",
                    latestCommand: "partial-tool latest")
            ]))
        let commands = MockCommandExecutor(results: [
            "partial-tool current": CommandResult(
                exitCode: 0, stdout: "partial-tool 1.0.0", stderr: ""),
            "partial-tool latest": CommandResult(
                exitCode: 1, stdout: "", stderr: "latest unavailable"),
        ])
        let service = registryService(paths: paths, commands: commands)

        let results = try service.check()
        let state = try stores.state.load()
        let error = try XCTUnwrap(results.first?.error)

        XCTAssertEqual(results.first?.status, .error)
        XCTAssertEqual(results.first?.current, "1.0.0")
        XCTAssertTrue(error.contains("latest.cmd exited 1"))
        XCTAssertEqual(state.items["partial-tool"]?.current, "1.0.0")
    }

    func testCheckHonorsTTLUnlessForced() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        try stores.manifest.save(
            manifest(items: [
                recipe(
                    id: "cached", currentCommand: "cached current", latestCommand: "cached latest")
            ]))
        try stores.state.save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "cached": ItemState(
                        current: "1.0.0",
                        latest: "1.1.0",
                        status: .outdated,
                        lastChecked: now.addingTimeInterval(-60),
                        error: nil,
                        backoffUntil: nil
                    )
                ]))
        let commands = MockCommandExecutor(results: [
            "cached current": CommandResult(exitCode: 0, stdout: "cached 1.1.0", stderr: ""),
            "cached latest": CommandResult(exitCode: 0, stdout: "cached 1.1.0", stderr: ""),
        ])
        let service = registryService(paths: paths, commands: commands)

        let cached = try service.check(ids: ["cached"], force: false)
        XCTAssertEqual(cached.first?.status, .outdated)
        XCTAssertTrue(commands.commands.isEmpty)

        let forced = try service.check(ids: ["cached"], force: true)
        XCTAssertEqual(forced.first?.status, .ok)
        XCTAssertEqual(commands.commands.map(\.command), ["cached current", "cached latest"])
    }

    func testCheckMarksUnapprovedCommandRecipeAsUntrusted() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        var item = recipe(
            id: "unsafe", currentCommand: "unsafe current", latestCommand: "unsafe latest")
        item.trust.approvedCommands = [:]
        try stores.manifest.save(manifest(items: [item]))
        let commands = MockCommandExecutor(results: [:])
        let service = registryService(paths: paths, commands: commands)

        let results = try service.check()
        let state = try stores.state.load()

        XCTAssertEqual(results.first?.status, .untrusted)
        XCTAssertEqual(state.items["unsafe"]?.status, .untrusted)
        XCTAssertTrue(commands.commands.isEmpty)
    }

    func testApprovalsReturnsSortedCommandApprovalStatuses() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        var item = recipe(id: "tool", currentCommand: "tool current", latestCommand: "tool latest")
        item.update.cwd = "/tmp/tool"
        item.trust.approvedCommands = [:]
        TestApprovals.approveAllCommands(in: &item)
        try stores.manifest.save(manifest(items: [item]))
        let service = registryService(paths: paths, commands: MockCommandExecutor(results: [:]))

        let approvals = try service.approvals(id: "tool")

        XCTAssertEqual(approvals.map(\.field), ["check.cmd", "latest.cmd", "update.cmd"])
        XCTAssertTrue(approvals.allSatisfy(\.approved))
        XCTAssertEqual(approvals.first { $0.field == "check.cmd" }?.command, "tool current")
        XCTAssertEqual(approvals.first { $0.field == "update.cmd" }?.cwd, "/tmp/tool")
    }

    func testApproveRejectsInvalidManifestWithoutSavingApproval() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        var item = recipe(id: "tool", currentCommand: "tool current", latestCommand: "tool latest")
        item.update.cmd = "OPENROUTER_API_KEY=sk-or-v1-secret-value tool update"
        item.trust.approvedCommands = [:]
        try stores.manifest.save(manifest(items: [item]))
        let service = registryService(paths: paths, commands: MockCommandExecutor(results: [:]))

        XCTAssertThrowsError(try service.approve(id: "tool", field: "update.cmd")) { error in
            guard case RegistryError.invalidManifest(let errors) = error else {
                return XCTFail("expected invalid manifest, got \(error)")
            }
            XCTAssertTrue(errors.contains("items[0].update.cmd: must not contain literal secrets"))
        }
        let stored = try XCTUnwrap(stores.manifest.loadExistingOrEmpty().item(id: "tool"))
        XCTAssertNil(stored.trust.approvedCommands["update.cmd"])
    }

    func testRegistryErrorDescriptionsRedactSecretLikeValues() {
        let secret = "sk-or-v1-secret-value"
        let errors: [RegistryError] = [
            .itemNotFound(secret),
            .missingCurrentVersion(secret),
            .duplicateItem(secret),
            .invalidManifest(["bad value \(secret)"]),
            .commandFailed("stderr \(secret)"),
            .commandFieldNotFound(secret),
            .checkFileNotReadable("/tmp/\(secret)"),
        ]

        for error in errors {
            let message = String(describing: error)
            XCTAssertTrue(message.contains("[REDACTED]"), "\(error)")
            XCTAssertFalse(message.contains(secret), "\(error)")
        }
    }

    func testCheckEmitsProgressEventsFromCoreContract() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        try stores.manifest.save(
            manifest(items: [
                recipe(id: "tool", currentCommand: "tool current", latestCommand: "tool latest")
            ]))
        let commands = MockCommandExecutor(results: [
            "tool current": CommandResult(exitCode: 0, stdout: "tool 1.0.0", stderr: ""),
            "tool latest": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
        ])
        let service = registryService(paths: paths, commands: commands)
        var events: [CheckProgressEvent] = []

        let results = try service.check { event in
            events.append(event)
        }

        XCTAssertEqual(results.map(\.status), [.outdated])
        XCTAssertEqual(events.map(\.phase), [.itemStarted, .itemFinished])
        XCTAssertEqual(events.map(\.id), ["tool", "tool"])
        XCTAssertNil(events[0].result)
        XCTAssertEqual(events[1].result?.status, .outdated)
    }

    func testAddRecipeCreatesFreshManifestWithInjectedClock() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let service = registryService(paths: paths, commands: MockCommandExecutor(results: [:]))

        let outcome = try service.addRecipe(
            recipe(id: "tool", currentCommand: "tool current", latestCommand: "tool latest"),
            replace: false
        )
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(outcome, .added)
        XCTAssertEqual(stored.provenance.createdAt, now)
        XCTAssertEqual(stored.provenance.updatedAt, now)
        XCTAssertEqual(stored.items.map(\.id), ["tool"])
    }

    func testAddRecipeValidatesExistingManifestBeforeDuplicateLookup() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        var existing = recipe(
            id: "tool", currentCommand: "tool current", latestCommand: "tool latest")
        existing.update.cmd = "OPENROUTER_API_KEY=sk-or-v1-secret-value tool update"
        try stores.manifest.save(manifest(items: [existing]))
        let service = registryService(paths: paths, commands: MockCommandExecutor(results: [:]))

        XCTAssertThrowsError(
            try service.addRecipe(
                recipe(id: "tool", currentCommand: "new current", latestCommand: "new latest"),
                replace: false
            )
        ) { error in
            guard case RegistryError.invalidManifest(let errors) = error else {
                return XCTFail("expected invalid manifest, got \(error)")
            }
            XCTAssertTrue(errors.contains("items[0].update.cmd: must not contain literal secrets"))
        }
    }

    func testImportManifestCreatesFreshManifestWithInjectedClock() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let service = registryService(paths: paths, commands: MockCommandExecutor(results: [:]))

        let summary = try service.importManifest(
            manifest(items: [
                recipe(id: "tool", currentCommand: "tool current", latestCommand: "tool latest")
            ]),
            replace: false
        )
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(summary.added, ["tool"])
        XCTAssertEqual(stored.provenance.createdAt, now)
        XCTAssertEqual(stored.provenance.updatedAt, now)
        XCTAssertEqual(stored.items.map(\.id), ["tool"])
    }

    func testImportManifestValidatesExistingManifestBeforeDuplicateLookup() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stores = Stores(paths: paths)
        var existing = recipe(
            id: "tool", currentCommand: "tool current", latestCommand: "tool latest")
        existing.update.cmd = "OPENROUTER_API_KEY=sk-or-v1-secret-value tool update"
        try stores.manifest.save(manifest(items: [existing]))
        let service = registryService(paths: paths, commands: MockCommandExecutor(results: [:]))

        XCTAssertThrowsError(
            try service.importManifest(
                manifest(items: [
                    recipe(id: "tool", currentCommand: "new current", latestCommand: "new latest")
                ]),
                replace: false
            )
        ) { error in
            guard case RegistryError.invalidManifest(let errors) = error else {
                return XCTFail("expected invalid manifest, got \(error)")
            }
            XCTAssertTrue(errors.contains("items[0].update.cmd: must not contain literal secrets"))
        }
    }

    private func registryService(
        paths: AppPaths,
        commands: MockCommandExecutor,
        environment: [String: String] = [:]
    ) -> RegistryService {
        RegistryService(
            manifestStore: ManifestStore(paths: paths),
            stateStore: StateStore(paths: paths),
            config: Config.default,
            httpClient: MockHTTPClient(responses: [:]),
            commandRunner: commands,
            now: { self.now },
            environment: environment,
            historyStore: HistoryStore(paths: paths)
        )
    }

    private func manifest(items: [Recipe]) -> Manifest {
        Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
    }

    private func recipe(id: String, currentCommand: String, latestCommand: String) -> Recipe {
        var item = Recipe(
            id: id,
            name: id,
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: id, branch: nil),
            versionScheme: .semver,
            check: .command(currentCommand),
            latest: LatestSpec(strategy: .cmd, cmd: latestCommand, pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "\(id) update", cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &item)
        return item
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-registry-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct Stores {
        var manifest: ManifestStore
        var state: StateStore

        init(paths: AppPaths) {
            manifest = ManifestStore(paths: paths)
            state = StateStore(paths: paths)
        }
    }
}
