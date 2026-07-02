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
        XCTAssertTrue(result.stderr.contains("remove cancelled"))
        XCTAssertNotNil(manifest.item(id: "tool"))
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

    func testApproveListAndRevokeCommandFields() throws {
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

        let approve = try CLIProcess.run(["approve", "tool", "--field", "update.cmd"], home: home)
        var manifest = try ManifestStore(paths: paths).load()
        var stored = try XCTUnwrap(manifest.item(id: "tool"))

        XCTAssertEqual(approve.exitCode, 0)
        XCTAssertEqual(stored.trust.level, .trusted)
        XCTAssertNotNil(stored.trust.approvedCommands["update.cmd"])
        XCTAssertNil(stored.trust.approvedCommands["check.cmd"])

        let list = try CLIProcess.run(["approvals", "tool"], home: home)
        XCTAssertEqual(list.exitCode, 0)
        XCTAssertTrue(list.stdout.contains("update.cmd\tapproved"))
        XCTAssertTrue(list.stdout.contains("check.cmd\tunapproved"))

        let listJSON = try CLIProcess.run(["approvals", "tool", "--json"], home: home)
        XCTAssertEqual(listJSON.exitCode, 0)
        XCTAssertTrue(listJSON.stdout.contains(#""command":"printf updated""#))

        let revoke = try CLIProcess.run(["revoke", "tool", "--field", "update.cmd"], home: home)
        manifest = try ManifestStore(paths: paths).load()
        stored = try XCTUnwrap(manifest.item(id: "tool"))

        XCTAssertEqual(revoke.exitCode, 0)
        XCTAssertNil(stored.trust.approvedCommands["update.cmd"])
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
        try ManifestStore(paths: paths).save(Manifest(
            schemaVersion: 1,
            items: [recipe()],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        ))
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
