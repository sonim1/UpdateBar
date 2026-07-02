import Foundation
import XCTest
import UpdateBarCore

final class ManageItemCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testPinUsesCurrentStateVersionAndUnpinClearsIt() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let pinResult = try CLIProcess.run(["pin", "tool"], home: home)
        var manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(pinResult.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.pin, "1.0.0")

        let unpinResult = try CLIProcess.run(["unpin", "tool"], home: home)
        manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(unpinResult.exitCode, 0)
        XCTAssertNil(manifest.item(id: "tool")?.pin)
    }

    func testPinWithoutStoredCurrentVersionDoesNotCreateState() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifestOnly(paths: paths)

        let result = try CLIProcess.run(["pin", "tool"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("tool: current version is unavailable"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
    }

    func testEnableAndDisableToggleItem() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let disableResult = try CLIProcess.run(["disable", "tool"], home: home)
        var manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(disableResult.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.enabled, false)

        let enableResult = try CLIProcess.run(["enable", "tool"], home: home)
        manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(enableResult.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.enabled, true)
    }

    func testRemoveDeletesManifestItemAndState() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let result = try CLIProcess.run(["remove", "tool", "--yes"], home: home)
        let manifest = try ManifestStore(paths: paths).load()
        let state = try StateStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNil(manifest.item(id: "tool"))
        XCTAssertNil(state.items["tool"])
    }

    func testRemoveWithoutYesRequiresPromptConfirmation() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let result = try CLIProcess.run(["remove", "tool"], home: home)
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "Remove tool? Type yes to continue: \nremove cancelled\n")
        XCTAssertTrue(result.stderr.contains("remove cancelled"))
        XCTAssertNotNil(manifest.item(id: "tool"))
    }

    func testRemoveWithBlankConfirmationDoesNotDoubleSpaceError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let result = try CLIProcess.run(["remove", "tool"], home: home, stdin: "\n")

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "Remove tool? Type yes to continue: \nremove cancelled\n")
    }

    func testRemoveWithoutYesJSONReturnsErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let result = try CLIProcess.run(["remove", "tool", "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains("remove cancelled"))
    }

    func testRemoveMissingItemDoesNotPrompt() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")

        let result = try CLIProcess.run(["remove", "missing"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("missing: item not found"))
        XCTAssertTrue(result.stderr.contains("updatebar status"))
        XCTAssertFalse(result.stderr.contains("Remove missing?"))
        XCTAssertFalse(result.stderr.contains("remove cancelled"))
    }

    func testRemoveMissingItemJSONReportsRegistryError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(["remove", "missing", "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(payload.code, "registry_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("missing: item not found") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar status") })
        XCTAssertFalse(payload.errors.contains("remove cancelled"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
    }

    func testApprovalsMissingItemJSONSuggestsStatus() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(["approvals", "missing", "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(payload.code, "registry_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("missing: item not found") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar status") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
    }

    func testMissingItemMutationsDoNotCreateManifest() throws {
        let commands = [
            ["pin", "missing", "1.0.0", "--json"],
            ["unpin", "missing", "--json"],
            ["disable", "missing", "--json"],
            ["enable", "missing", "--json"],
            ["approve", "missing", "--json"],
            ["revoke", "missing", "--field", "update.cmd", "--json"],
            ["remove", "missing", "--yes", "--json"],
        ]

        for command in commands {
            let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
            let paths = AppPaths(homeDirectory: home)

            let result = try CLIProcess.run(command, home: home)

            XCTAssertEqual(result.exitCode, 1, command.joined(separator: " "))
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: paths.manifestFile.path),
                command.joined(separator: " ")
            )
        }
    }

    func testApproveInvalidFieldJSONSuggestsApprovals() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let result = try CLIProcess.run(["approve", "tool", "--field", "install.cmd", "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(payload.code, "registry_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("install.cmd: command field not found") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar approvals tool") })
    }

    func testRevokeInvalidFieldHumanSuggestsApprovals() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let result = try CLIProcess.run(["revoke", "tool", "--field", "install.cmd"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("install.cmd: command field not found"))
        XCTAssertTrue(result.stderr.contains("updatebar approvals tool"))
    }

    func testApproveListAndRevokeCommandFields() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        var item = recipe()
        item.update.cwd = "/tmp/tool"
        item.trust.level = .untrusted
        item.trust.approvedCommands = [:]
        try ManifestStore(paths: paths).save(Manifest(
            schemaVersion: 1,
            items: [item],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        ))

        let approve = try CLIProcess.run(["approve", "tool", "--field", "update.cmd"], home: home)
        var manifest = try ManifestStore(paths: paths).load()
        var stored = try XCTUnwrap(manifest.item(id: "tool"))

        XCTAssertEqual(approve.exitCode, 0)
        XCTAssertEqual(stored.trust.level, .trusted)
        XCTAssertNotNil(stored.trust.approvedCommands["update.cmd"])
        XCTAssertNil(stored.trust.approvedCommands["check.cmd"])
        XCTAssertTrue(approve.stdout.contains("approved tool update.cmd"))
        XCTAssertTrue(approve.stdout.contains("Next"))
        XCTAssertTrue(approve.stdout.contains("updatebar approvals tool"))
        XCTAssertFalse(approve.stdout.contains("updatebar check tool"))

        let list = try CLIProcess.run(["approvals", "tool"], home: home)
        XCTAssertEqual(list.exitCode, 0)
        XCTAssertTrue(list.stdout.contains("FIELD\tSTATUS\tCOMMAND\tDETAIL"))
        XCTAssertTrue(list.stdout.contains("update.cmd\tapproved\tprintf updated\tcwd=/tmp/tool"))
        XCTAssertTrue(list.stdout.contains("check.cmd\tunapproved\tprintf 'tool 1.0.0'\t"))
        XCTAssertTrue(list.stdout.contains("latest.cmd\tunapproved\tprintf 'tool 1.1.0'\t"))
        XCTAssertTrue(list.stdout.contains("Next"))
        XCTAssertTrue(list.stdout.contains("updatebar approve tool --field check.cmd"))
        XCTAssertTrue(list.stdout.contains("updatebar approve tool --field latest.cmd"))
        XCTAssertFalse(list.stdout.contains("updatebar approve tool --field update.cmd"))

        let listJSON = try CLIProcess.run(["approvals", "tool", "--json"], home: home)
        XCTAssertEqual(listJSON.exitCode, 0)
        XCTAssertTrue(listJSON.stdout.contains(#""command":"printf updated""#))

        let revoke = try CLIProcess.run(["revoke", "tool", "--field", "update.cmd"], home: home)
        manifest = try ManifestStore(paths: paths).load()
        stored = try XCTUnwrap(manifest.item(id: "tool"))

        XCTAssertEqual(revoke.exitCode, 0)
        XCTAssertNil(stored.trust.approvedCommands["update.cmd"])
        XCTAssertTrue(revoke.stdout.contains("revoked tool update.cmd"))
        XCTAssertTrue(revoke.stdout.contains("Next"))
        XCTAssertTrue(revoke.stdout.contains("updatebar approvals tool"))
        XCTAssertFalse(revoke.stdout.contains("updatebar check tool"))
    }

    func testApprovalsHumanAllApprovedPrintsCheckNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let result = try CLIProcess.run(["approvals", "tool"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("FIELD\tSTATUS\tCOMMAND\tDETAIL"))
        XCTAssertTrue(result.stdout.contains("check.cmd\tapproved"))
        XCTAssertTrue(result.stdout.contains("latest.cmd\tapproved"))
        XCTAssertTrue(result.stdout.contains("update.cmd\tapproved"))
        XCTAssertTrue(result.stdout.contains("All command fields approved."))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar check tool"))
        XCTAssertFalse(result.stdout.contains("updatebar approve tool"))
    }

    func testApproveAllHumanPrintsCheckNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        var item = recipe()
        item.trust.level = .untrusted
        item.trust.approvedCommands = [:]
        try ManifestStore(paths: paths).save(Manifest(
            schemaVersion: 1,
            items: [item],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        ))

        let result = try CLIProcess.run(["approve", "tool"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("approved tool all"))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar check tool"))
        XCTAssertFalse(result.stdout.contains("updatebar approvals tool"))
    }

    func testMutatingManageCommandsSupportJSONOutput() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveFixture(paths: paths)

        let pin = try CLIProcess.run(["pin", "tool", "--json"], home: home)
        let disable = try CLIProcess.run(["disable", "tool", "--json"], home: home)
        let enable = try CLIProcess.run(["enable", "tool", "--json"], home: home)
        let approve = try CLIProcess.run(["approve", "tool", "--field", "update.cmd", "--json"], home: home)
        let revoke = try CLIProcess.run(["revoke", "tool", "--field", "update.cmd", "--json"], home: home)
        let unpin = try CLIProcess.run(["unpin", "tool", "--json"], home: home)
        let remove = try CLIProcess.run(["remove", "tool", "--yes", "--json"], home: home)

        for result in [pin, disable, enable, approve, revoke, unpin, remove] {
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertTrue(result.stdout.contains(#""ok":true"#))
            XCTAssertTrue(result.stdout.contains(#""id":"tool""#))
        }
    }

    private func saveFixture(paths: AppPaths) throws {
        try saveManifestOnly(paths: paths)
        try StateStore(paths: paths).save(State(schemaVersion: 1, generatedAt: now, items: [
            "tool": ItemState(
                current: "1.0.0",
                latest: "1.1.0",
                status: .outdated,
                lastChecked: now,
                error: nil,
                backoffUntil: nil
            )
        ]))
    }

    private func saveManifestOnly(paths: AppPaths) throws {
        try ManifestStore(paths: paths).save(Manifest(
            schemaVersion: 1,
            items: [recipe()],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        ))
    }

    private func recipe() -> Recipe {
        var item = Recipe(
            id: "tool",
            name: "Tool",
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: "tool", branch: nil),
            versionScheme: .semver,
            check: .command("printf 'tool 1.0.0'"),
            latest: LatestSpec(strategy: .cmd, cmd: "printf 'tool 1.1.0'", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "printf updated", cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &item)
        return item
    }

    private struct ErrorEnvelope: Decodable {
        var ok: Bool
        var code: String
        var errors: [String]
    }
}
