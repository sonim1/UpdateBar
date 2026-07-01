import Foundation
import XCTest
import UpdateBarCore

final class GuideTemplateCommandTests: XCTestCase {
    func testGuideAgentPrintsSafeAgentWorkflow() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-guide-tests")

        let result = try CLIProcess.run(["guide", "agent"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Do not approve commands silently"))
        XCTAssertTrue(result.stdout.contains("updatebar validate"))
        XCTAssertTrue(result.stdout.contains("updatebar add --from"))
    }

    func testTemplateRecipePrintsValidUntrustedRecipeJSON() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-template-tests")

        let result = try CLIProcess.run(["template", "recipe", "--kind", "npm"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let recipe = try JSONDecoder.updateBar.decode(Recipe.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(recipe.id, "example-npm-tool")
        XCTAssertEqual(recipe.source.kind, .npm)
        XCTAssertEqual(recipe.latest.strategy, .npmRegistry)
        XCTAssertEqual(recipe.trust.level, .untrusted)
        XCTAssertEqual(recipe.trust.approvedCommands, [:])
    }

    func testTemplateRecipeCanBeValidatedByCLI() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-template-tests")
        let template = try CLIProcess.run(["template", "recipe", "--kind", "npm"], home: home)
        let file = home.appendingPathComponent("recipe.json")
        try Data(template.stdout.utf8).write(to: file)

        let validation = try CLIProcess.run(["validate", file.path, "--json"], home: home)

        XCTAssertEqual(validation.exitCode, 0)
        XCTAssertTrue(validation.stdout.contains(#""valid":true"#))
    }

    func testSchemaCommandPrintsRecipeJSONSchema() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-schema-tests")

        let result = try CLIProcess.run(["schema"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        XCTAssertEqual(object?["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertTrue(result.stdout.contains(#""schema_version""#))
        XCTAssertTrue(result.stdout.contains(#""latest""#))
        XCTAssertFalse(result.stdout.contains(#""jq""#))
    }

    func testSchemaCommandRejectsUnsupportedJSONFlag() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-schema-json-tests")

        let result = try CLIProcess.run(["schema", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue((result.stdout + result.stderr).contains("Unknown option '--json'"))
        XCTAssertTrue((result.stdout + result.stderr).contains("Usage: updatebar schema"))
    }

    func testGuideRecipePrintsRecipeAuthoringGuide() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-guide-tests")

        let result = try CLIProcess.run(["guide", "recipe"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Recipe authoring"))
        XCTAssertTrue(result.stdout.contains("version_parse.regex"))
    }

    func testTemplateRecipeAcceptsAgentOverrides() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-template-tests")

        let result = try CLIProcess.run(
            ["template", "recipe", "--kind", "npm", "--id", "ripgrep", "--name", "Ripgrep", "--source", "ripgrep"],
            home: home
        )

        XCTAssertEqual(result.exitCode, 0)
        let recipe = try JSONDecoder.updateBar.decode(Recipe.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(recipe.id, "ripgrep")
        XCTAssertEqual(recipe.name, "Ripgrep")
        XCTAssertEqual(recipe.source.ref, "ripgrep")
    }

    func testTemplateManifestPrintsSingleItemManifest() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-template-tests")

        let result = try CLIProcess.run(["template", "manifest", "--kind", "npm"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.items.count, 1)
        XCTAssertEqual(manifest.items.first?.trust.level, .untrusted)
    }
}
