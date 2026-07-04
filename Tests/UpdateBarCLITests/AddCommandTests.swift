import Foundation
import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class AddCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testManualAddDryRunPrintsRecipeAndDoesNotWriteManifest() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let file = try writeRecipe(home: home, recipe: recipe(id: "dry-run"))

        let result = try CLIProcess.run(
            ["add", "--from", file.path, "--dry-run", "--json"], home: home)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(stored.items.isEmpty)
        let payload = try JSONDecoder.updateBar.decode(
            AddPayload.self, from: Data(result.stdout.utf8))
        XCTAssertTrue(payload.valid)
        XCTAssertEqual(payload.recipe?.id, "dry-run")
        XCTAssertEqual(payload.recipe?.trust.level, .untrusted)
        XCTAssertNil(payload.outcome)
    }

    func testManualAddDryRunHumanModeDoesNotSayAdded() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let file = try writeRecipe(home: home, recipe: recipe(id: "dry-run"))

        let result = try CLIProcess.run(["add", "--from", file.path, "--dry-run"], home: home)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(stored.items.isEmpty)
        XCTAssertTrue(result.stdout.contains("valid dry-run"))
        XCTAssertTrue(result.stdout.contains("dry run: not saved"))
        XCTAssertFalse(result.stdout.contains("added dry-run"))
    }

    func testManualAddFromManifestStoresUntrustedRecipe() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let file = try writeManifest(home: home, items: [recipe(id: "manual")])

        let result = try CLIProcess.run(["add", "--from", file.path, "--json"], home: home)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            AddPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.outcome, .added)
        XCTAssertEqual(stored.item(id: "manual")?.trust.level, .untrusted)
        XCTAssertEqual(stored.item(id: "manual")?.trust.approvedCommands, [:])
    }

    func testManualAddHumanModePrintsApprovalNextStepBeforeCheck() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let file = try writeRecipe(home: home, recipe: recipe(id: "manual"))

        let result = try CLIProcess.run(["add", "--from", file.path], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("added manual"))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar approvals manual"))
        XCTAssertFalse(result.stdout.contains("updatebar check manual"))
    }

    func testAddWithoutInputReportsActionableRecipeInputError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")

        let result = try CLIProcess.run(["add"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(
            result.stderr,
            "add requires recipe input; pass --from <file> or --from - for stdin\n")
    }

    func testAddJSONWithoutInputDoesNotWritePromptToStderr() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")

        let result = try CLIProcess.run(["add", "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(
            payload.errors.contains(
                "add requires recipe input; pass --from <file> or --from - for stdin"))
    }

    #if os(macOS)
        func testAddJSONWithTTYDoesNotWaitForWizardInput() throws {
            let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")

            let result = try CLIProcess.runWithOpenTTYUntilExit(
                ["add", "--json"],
                home: home,
                timeout: 0.5
            )

            let finished = try XCTUnwrap(result, "add --json should not wait for TTY wizard input")
            XCTAssertEqual(finished.exitCode, 1)
            XCTAssertTrue(finished.stdout.contains("usage_error"))
            XCTAssertFalse(finished.stderr.contains("id"))
        }
    #endif

    func testManualAddRejectsMalformedManifestWithValidationErrors() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let file = home.appendingPathComponent("broken-manifest.json")
        try Data(
            """
            {
              "schema_version": 1,
              "provenance": {
                "created_by": "updatebar",
                "created_at": "2026-06-09T00:00:00Z",
                "updated_at": "2026-06-09T00:00:00Z"
              }
            }
            """.utf8
        ).write(to: file)

        let result = try CLIProcess.run(["add", "--from", file.path, "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("items: required"))
        XCTAssertFalse(result.stdout.contains("CodingKeys"))
    }

    func testManualAddRejectsMalformedRecipeWithValidationErrors() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let file = home.appendingPathComponent("broken-recipe.json")
        try Data(
            """
            {
              "id": "tool"
            }
            """.utf8
        ).write(to: file)

        let result = try CLIProcess.run(["add", "--from", file.path, "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("$.name: required"))
        XCTAssertTrue(result.stdout.contains("$.source: required"))
        XCTAssertFalse(result.stdout.contains("CodingKeys"))
    }

    func testManualAddMissingInputFileJSONReturnsUsageError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let file = home.appendingPathComponent("missing-recipe.json")

        let result = try CLIProcess.run(["add", "--from", file.path, "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("missing-recipe.json") })
    }

    func testManualAddRejectsDuplicateID() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool")]))
        let file = try writeRecipe(home: home, recipe: recipe(id: "tool"))

        let result = try CLIProcess.run(["add", "--from", file.path, "--json"], home: home)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(try ManifestStore(paths: paths).load().items.count, 1)
    }

    func testManualAddReplaceUpdatesExistingRecipe() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [recipe(id: "tool", name: "Original")]))
        let file = try writeRecipe(home: home, recipe: recipe(id: "tool", name: "Replacement"))

        let result = try CLIProcess.run(
            ["add", "--from", file.path, "--replace", "--json"], home: home)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            AddPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.outcome, .replaced)
        XCTAssertEqual(stored.item(id: "tool")?.name, "Replacement")
        XCTAssertEqual(stored.item(id: "tool")?.trust.level, .untrusted)
    }

    func testManualAddReplaceHumanModeSaysReplaced() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [recipe(id: "tool", name: "Original")]))
        let file = try writeRecipe(home: home, recipe: recipe(id: "tool", name: "Replacement"))

        let result = try CLIProcess.run(["add", "--from", file.path, "--replace"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("replaced tool"))
        XCTAssertFalse(result.stdout.contains("added tool"))
        XCTAssertTrue(result.stdout.contains("updatebar approvals tool"))
    }

    func testAIAddFlagsAreRemovedFromCLI() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let result = try CLIProcess.run(["add", "--ai", "--from", "anything"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("add --ai was removed"))
        XCTAssertTrue(result.stderr.contains("Run updatebar template recipe"))
        XCTAssertTrue(result.stderr.contains("updatebar add --from <file>"))
    }

    func testAddProviderFlagIsRemovedFromCLI() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let result = try CLIProcess.run(
            ["add", "--provider", "openrouter", "--from", "anything"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("add --provider was removed"))
        XCTAssertTrue(result.stderr.contains("Recipe authoring belongs to external agents"))
        XCTAssertTrue(result.stderr.contains("updatebar add --from <file>"))
    }

    func testAddTrustFlagIsRemovedFromCLI() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let result = try CLIProcess.run(["add", "--trust", "--from", "anything"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("add --trust was removed"))
        XCTAssertTrue(result.stderr.contains("New recipes are saved untrusted"))
        XCTAssertTrue(result.stderr.contains("updatebar approvals <id>"))
    }

    func testAddWithoutSourceRejectsLegacyWizardAnswers() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let input = legacyWizardInput()

        let result = try CLIProcess.run(["add", "--json"], home: home, stdin: input)
        let stored = try ManifestStore(paths: paths).load()
        let payload = try JSONDecoder.updateBar.decode(
            ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertNil(stored.item(id: "wizard"))
        XCTAssertTrue(
            payload.errors.contains(
                "add requires recipe input; pass --from <file> or --from - for stdin"))
    }

    func testAddManualFlagIsRemovedFromCLI() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-add-tests")

        let result = try CLIProcess.run(["add", "--manual", "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertTrue(payload.errors.contains { $0.contains("add --manual was removed") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar add --from <file>") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar add --from -") })
    }

    private func legacyWizardInput() -> String {
        """
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
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &item)
        return item
    }

    private struct ErrorEnvelope: Decodable {
        var ok: Bool
        var code: String
        var errors: [String]
    }

    private struct AddPayload: Decodable {
        var valid: Bool
        var recipe: Recipe?
        var outcome: AddRecipeOutcome?
    }
}
