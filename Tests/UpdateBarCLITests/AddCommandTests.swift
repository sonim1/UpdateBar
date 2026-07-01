import Foundation
import XCTest
import UpdateBarCore

final class AddCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testManualAddDryRunPrintsRecipeAndDoesNotWriteManifest() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let file = try writeRecipe(home: home, recipe: recipe(id: "dry-run"))

        let result = try CLIProcess.run(["add", "--from", file.path, "--dry-run", "--json"], home: home)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(stored.items.isEmpty)
        let payload = try JSONDecoder.updateBar.decode(AddPayload.self, from: Data(result.stdout.utf8))
        XCTAssertTrue(payload.valid)
        XCTAssertEqual(payload.recipe?.id, "dry-run")
        XCTAssertEqual(payload.recipe?.trust.level, .untrusted)
    }

    func testManualAddFromManifestStoresUntrustedRecipe() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let file = try writeManifest(home: home, items: [recipe(id: "manual")])

        let result = try CLIProcess.run(["add", "--from", file.path, "--json"], home: home)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(stored.item(id: "manual")?.trust.level, .untrusted)
        XCTAssertEqual(stored.item(id: "manual")?.trust.approvedCommands, [:])
    }

    func testManualAddRejectsDuplicateID() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool")]))
        let file = try writeRecipe(home: home, recipe: recipe(id: "tool"))

        let result = try CLIProcess.run(["add", "--from", file.path, "--json"], home: home)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(try ManifestStore(paths: paths).load().items.count, 1)
    }

    func testManualAddReplaceUpdatesExistingRecipe() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool", name: "Original")]))
        let file = try writeRecipe(home: home, recipe: recipe(id: "tool", name: "Replacement"))

        let result = try CLIProcess.run(["add", "--from", file.path, "--replace", "--json"], home: home)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(stored.item(id: "tool")?.name, "Replacement")
        XCTAssertEqual(stored.item(id: "tool")?.trust.level, .untrusted)
    }

    func testManualAddTrustCanApproveHeadlesslyWithYes() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let file = try writeRecipe(home: home, recipe: recipe(id: "trusted"))

        let result = try CLIProcess.run(["add", "--from", file.path, "--trust", "--yes", "--json"], home: home)
        let stored = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "trusted"))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(stored.trust.level, .trusted)
        XCTAssertFalse(stored.trust.approvedCommands.isEmpty)
    }

    func testManualAddTrustWithoutYesRequiresPromptConfirmation() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let file = try writeRecipe(home: home, recipe: recipe(id: "denied"))

        let result = try CLIProcess.run(["add", "--from", file.path, "--trust"], home: home)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("command approval cancelled"))
        XCTAssertNil(stored.item(id: "denied"))
    }

    func testAIAddFlagsAreRemovedFromCLI() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let result = try CLIProcess.run(["add", "--ai", "--from", "anything"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("Unknown option '--ai'"))
    }

    func testManualWizardCreatesUntrustedRecipe() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let input = """
        wizard
        Wizard Tool
        cli

        custom
        wizard

        semver
        printf 'wizard 1.0.0'
        cmd
        printf 'wizard 1.1.0'

        ([0-9]+\\.[0-9]+\\.[0-9]+)
        printf updated

        """

        let result = try CLIProcess.run(["add", "--manual", "--json"], home: home, stdin: input)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(stored.item(id: "wizard")?.name, "Wizard Tool")
        XCTAssertEqual(stored.item(id: "wizard")?.trust.level, .untrusted)
    }

    private func writeRecipe(home: URL, recipe: Recipe) throws -> URL {
        let file = home.appendingPathComponent("\(recipe.id).json")
        try JSONEncoder.updateBar.encode(recipe).write(to: file)
        return file
    }

    private func writeManifest(home: URL, items: [Recipe]) throws -> URL {
        let file = home.appendingPathComponent("manifest-import.json")
        try JSONEncoder.updateBar.encode(manifest(items: items)).write(to: file)
        return file
    }

    private func manifest(items: [Recipe]) -> Manifest {
        Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
    }

    private func recipe(id: String, name: String? = nil) -> Recipe {
        var item = Recipe(
            id: id,
            name: name ?? id,
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
            notify: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &item)
        return item
    }

    private struct AddPayload: Decodable {
        var valid: Bool
        var recipe: Recipe?
    }
}
