import Foundation
import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class UpdateCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testUpdateSelectedItemJSONRunsAndRefreshesState() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.1.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "tool", "--yes", "--json"], home: home)
        let state = try StateStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        let results = try JSONDecoder.updateBar.decode(
            [UpdateResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results.map(\.outcome), [.updated])
        XCTAssertEqual(state.items["tool"]?.status, .ok)
        XCTAssertEqual(state.items["tool"]?.current, "1.1.0")
    }

    func testUpdateWithoutIDsReturnsPartialFailureExitCode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "bad", updateCommand: "printf 'sk-or-v1-%s' 'secret' >&2; exit 3",
                    currentCommand: "printf 'bad 1.0.0'"),
                recipe(
                    id: "good", updateCommand: "printf updated",
                    currentCommand: "printf 'good 1.1.0'"),
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "bad": itemState(status: .outdated),
                    "good": itemState(status: .outdated),
                ]))

        let result = try CLIProcess.run(["update", "--yes", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 2)
        let results = try JSONDecoder.updateBar.decode(
            [UpdateResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results.map(\.outcome), [.failed, .updated])
        XCTAssertFalse(results[0].error?.contains("sk-or-v1-secret") ?? true)
    }

    func testUpdateWithoutIDsDefaultsToAllOutdatedItems() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "one", updateCommand: "printf updated", currentCommand: "printf 'one 1.1.0'"
                ),
                recipe(
                    id: "two", updateCommand: "printf updated", currentCommand: "printf 'two 1.1.0'"
                ),
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "one": itemState(status: .outdated),
                    "two": itemState(status: .outdated),
                ]))

        let result = try CLIProcess.run(["update", "--yes", "--json"], home: home)

        guard result.exitCode == 0 else {
            XCTFail(
                "expected update without ids to default to all, got exit \(result.exitCode): \(result.stdout)"
            )
            return
        }
        let results = try JSONDecoder.updateBar.decode(
            [UpdateResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results.map(\.id), ["one", "two"])
        XCTAssertEqual(results.map(\.outcome), [.updated, .updated])
    }

    func testUpdateHumanEmptyResultExplainsNoUpdatesWereRun() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(["update", "--yes"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("No items registered."))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar init"))
        XCTAssertFalse(result.stdout.contains("No approved outdated items to update."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
    }

    func testUpdateHumanRegisteredItemsWithoutOutdatedStateDoesNotPrintInitNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.0.0'")
            ]))

        let result = try CLIProcess.run(["update", "--yes"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("ID\tOUTCOME\tCURRENT\tLATEST\tDETAIL"))
        XCTAssertTrue(result.stdout.contains("tool\tskipped_not_outdated\t-\t-\t"))
        XCTAssertFalse(result.stdout.contains("updatebar init"))
    }

    func testUpdateHumanMissingItemPrintsStatusNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")

        let result = try CLIProcess.run(["update", "missing", "--yes"], home: home)

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("ID\tOUTCOME\tCURRENT\tLATEST\tDETAIL"))
        XCTAssertTrue(result.stdout.contains("missing\tmissing\t-\t-\t"))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar status"))
    }

    func testUpdateHumanSkippedNotOutdatedPrintsCheckNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.0.0'")
            ]))

        let result = try CLIProcess.run(["update", "tool", "--yes"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("ID\tOUTCOME\tCURRENT\tLATEST\tDETAIL"))
        XCTAssertTrue(result.stdout.contains("tool\tskipped_not_outdated\t-\t-\t"))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar check tool"))
    }

    func testUpdateBlockedOnApprovalReturnsDistinctExitCode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        var item = recipe(
            id: "tool", updateCommand: "printf updated", currentCommand: "printf 'tool 1.0.0'")
        item.trust.level = .untrusted
        item.trust.approvedCommands = [:]
        try ManifestStore(paths: paths).save(manifest(items: [item]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "tool", "--yes", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 3)
        let results = try JSONDecoder.updateBar.decode(
            [UpdateResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results.map(\.outcome), [.skippedUntrusted])
    }

    func testUpdateHumanBlockedOnApprovalPrintsNextSteps() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        var item = recipe(
            id: "tool", updateCommand: "printf updated", currentCommand: "printf 'tool 1.0.0'")
        item.trust.level = .untrusted
        item.trust.approvedCommands = [:]
        try ManifestStore(paths: paths).save(manifest(items: [item]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "tool", "--yes"], home: home)

        XCTAssertEqual(result.exitCode, 3)
        XCTAssertTrue(result.stdout.contains("ID\tOUTCOME\tCURRENT\tLATEST\tDETAIL"))
        XCTAssertTrue(result.stdout.contains("tool\tskipped_untrusted\t1.0.0\t1.1.0\t"))
        XCTAssertTrue(result.stdout.contains("updatebar approvals tool"))
        XCTAssertFalse(result.stdout.contains("updatebar approve tool"))
    }

    func testUpdateJSONStreamEmitsLineDelimitedEvents() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.1.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "tool", "--yes", "--json-stream"], home: home)
        let events = try decodeEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(
            events.map(\.event), [.started, .log, .itemStarted, .itemFinished, .finished])
        XCTAssertEqual(events[2].itemId, "tool")
        XCTAssertEqual(events[3].result?.outcome, .updated)
        XCTAssertEqual(events[4].summary?.updated, 1)
        XCTAssertEqual(events[4].summary?.hardFailures, 0)
    }

    func testUpdateJSONStreamEmptyRegistryDoesNotCreateRegistryFiles() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(["update", "--yes", "--json-stream"], home: home)
        let events = try decodeEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(events.map(\.event), [.started, .log, .finished])
        XCTAssertEqual(events.last?.summary?.total, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
    }

    func testUpdateJSONStreamPreservesFailureExitCodeAndFinishedSummary() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "bad", updateCommand: "printf 'sk-or-v1-%s' 'secret' >&2; exit 3",
                    currentCommand: "printf 'bad 1.0.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "bad": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "bad", "--yes", "--json-stream"], home: home)
        let events = try decodeEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(
            events.map(\.event), [.started, .log, .itemStarted, .itemFinished, .finished])
        XCTAssertEqual(events[3].result?.outcome, .failed)
        XCTAssertFalse(events[3].result?.error?.contains("sk-or-v1-secret") ?? true)
        XCTAssertEqual(events[4].summary?.failed, 1)
        XCTAssertEqual(events[4].summary?.hardFailures, 1)
    }

    func testUpdateJSONWithoutYesSkipsExecutionWithoutPrompt() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.0.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "tool", "--json"], home: home)
        let results = try JSONDecoder.updateBar.decode(
            [UpdateResult].self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(results.map(\.outcome), [.cancelled])
    }

    func testUpdateJSONRedactsStoredVersionSecrets() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        let secret = "sk-or-v1-update-secret-value"
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.0.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": ItemState(
                        current: secret,
                        latest: secret,
                        status: .outdated,
                        lastChecked: now,
                        error: nil,
                        backoffUntil: nil
                    )
                ]))

        let result = try CLIProcess.run(["update", "tool", "--json"], home: home)
        let results = try JSONDecoder.updateBar.decode(
            [UpdateResult].self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertFalse(result.stdout.contains(secret))
        XCTAssertTrue(result.stdout.contains("[REDACTED]"))
        XCTAssertEqual(results.first?.current, "[REDACTED]")
        XCTAssertEqual(results.first?.latest, "[REDACTED]")
    }

    func testUpdateHumanCancelledWithoutYesPrintsYesNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.0.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "tool"], home: home)

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Type yes to continue"))
        XCTAssertTrue(result.stdout.contains("ID\tOUTCOME\tCURRENT\tLATEST\tDETAIL"))
        XCTAssertTrue(result.stdout.contains("tool\tcancelled\t1.0.0\t1.1.0\t"))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar update tool --yes"))
    }

    func testUpdateRejectsJSONAndJSONStreamTogether() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.0.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(
            ["update", "tool", "--yes", "--json", "--json-stream"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.stdout.isEmpty)
        XCTAssertTrue(result.stdout.contains("usage_error"))
        XCTAssertTrue(result.stdout.contains("--json and --json-stream cannot be combined"))
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testUpdateRejectsRemovedAllFlag() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.1.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(
            ["update", "--all", "--yes", "--json"],
            home: home
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("update --all was removed"))
        XCTAssertTrue(result.stdout.contains("Run updatebar update without ids"))
        XCTAssertFalse(result.stdout.contains("\"ok\":true"))
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testUpdateDeduplicatesIDs() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.1.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(
            ["update", "tool", "tool", "tool", "--yes", "--json"], home: home)
        let updated = try JSONDecoder.updateBar.decode(
            [UpdateResult].self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].outcome, .updated)
    }

    func testUpdateJSONStreamReportsCancellation() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(id: "slow", updateCommand: "sleep 5", currentCommand: "printf 'slow 1.0.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "slow": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.runAndInterrupt(
            ["update", "slow", "--yes", "--json-stream"],
            home: home,
            after: 0.5
        )
        let events = try decodeEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(
            events.map(\.event),
            [.started, .log, .itemStarted, .itemFinished, .cancelled, .finished])
        XCTAssertEqual(events[3].result?.outcome, .cancelled)
        XCTAssertEqual(events[4].summary?.cancelled, 1)
    }

    func testUpdateJSONStreamIncludesStableRunIDAcrossEvents() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.1.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "tool", "--yes", "--json-stream"], home: home)
        let rawEvents = try decodeRawEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 0)
        let runIDs = Set(rawEvents.compactMap { $0["run_id"] as? String })
        XCTAssertEqual(runIDs.count, 1)
        XCTAssertFalse(runIDs.first?.isEmpty ?? true)
    }

    func testUpdateJSONStreamWithoutYesSkipsExecutionWithoutPrompt() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.0.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "tool", "--json-stream"], home: home)
        let events = try decodeEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(
            events.map(\.event),
            [.started, .log, .itemStarted, .itemFinished, .cancelled, .finished])
        XCTAssertEqual(events[3].result?.outcome, .cancelled)
        XCTAssertEqual(events[4].summary?.cancelled, 1)
    }

    func testUpdateWithJSONSpaceSeparatedFalseFallsBackToHumanMode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(
                    id: "tool", updateCommand: "printf updated",
                    currentCommand: "printf 'tool 1.1.0'")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated)
                ]))

        let result = try CLIProcess.run(["update", "tool", "--yes", "--json", "off"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertTrue(result.stdout.contains("ID\tOUTCOME\tCURRENT\tLATEST\tDETAIL"))
        XCTAssertTrue(result.stdout.contains("tool\tupdated\t1.1.0\t1.1.0\t"))
        XCTAssertFalse(result.stdout.contains("\"id\""))
    }

    func testUpdateJSONStreamStopsAfterCancellation() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-update-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(id: "slow", updateCommand: "sleep 5", currentCommand: "printf 'slow 1.0.0'"),
                recipe(
                    id: "next", updateCommand: "printf updated",
                    currentCommand: "printf 'next 1.1.0'"),
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "slow": itemState(status: .outdated),
                    "next": itemState(status: .outdated),
                ]))

        let result = try CLIProcess.runAndInterrupt(
            ["update", "--yes", "--json-stream"],
            home: home,
            after: 0.5
        )
        let events = try decodeEvents(result.stdout)

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(events.filter { $0.event == .itemStarted }.map(\.itemId), ["slow"])
        XCTAssertEqual(events.filter { $0.event == .itemFinished }.map(\.itemId), ["slow"])
        XCTAssertEqual(events.last?.summary?.cancelled, 1)
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
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &item)
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

    private func decodeEvents(_ stdout: String) throws -> [MachineEvent] {
        try stdout.split(separator: "\n").map { line in
            try JSONDecoder.updateBar.decode(MachineEvent.self, from: Data(line.utf8))
        }
    }

    private func decodeRawEvents(_ stdout: String) throws -> [[String: Any]] {
        try stdout.split(separator: "\n").map { line in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try XCTUnwrap(object as? [String: Any])
        }
    }
}
