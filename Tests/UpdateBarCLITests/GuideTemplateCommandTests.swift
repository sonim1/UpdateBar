import Foundation
import XCTest
import UpdateBarCore

final class GuideTemplateCommandTests: XCTestCase {
    func testGuideAgentPrintsSafeAgentWorkflow() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-guide-tests")

        let result = try CLIProcess.run(["guide", "agent"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Do not approve commands silently"))
        XCTAssertTrue(result.stdout.contains("Repeat approval for each command field the user accepts"))
        XCTAssertTrue(result.stdout.contains("Common fields: check.cmd, latest.cmd, update.cmd"))
        XCTAssertTrue(result.stdout.contains("updatebar approve <id> --field check.cmd --json"))
        XCTAssertTrue(result.stdout.contains("updatebar approve <id> --field latest.cmd --json"))
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
        XCTAssertFalse(result.stdout.contains(#""notify""#))
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
        let rootProperties = try XCTUnwrap(object?["properties"] as? [String: Any])
        let provenance = try XCTUnwrap(rootProperties["provenance"] as? [String: Any])
        XCTAssertEqual(provenance["required"] as? [String], ["created_by", "created_at", "updated_at"])
        let provenanceProperties = try XCTUnwrap(provenance["properties"] as? [String: Any])
        XCTAssertEqual((provenanceProperties["created_by"] as? [String: Any])?["minLength"] as? Int, 1)
        XCTAssertEqual((provenanceProperties["created_at"] as? [String: Any])?["format"] as? String, "date-time")
        XCTAssertEqual((provenanceProperties["updated_at"] as? [String: Any])?["format"] as? String, "date-time")
        let recipe = try schemaRecipeDefinition(from: object)
        let required = try XCTUnwrap(recipe["required"] as? [String])
        XCTAssertFalse(required.contains("enabled"))
        XCTAssertFalse(required.contains("notify"))
        let properties = try XCTUnwrap(recipe["properties"] as? [String: Any])
        XCTAssertEqual(try boolDefault(in: properties, "requires_write", nestedIn: "update"), true)
        XCTAssertEqual(try boolDefault(in: properties, "enabled"), true)
        XCTAssertNil(properties["notify"])
        let trust = try XCTUnwrap(properties["trust"] as? [String: Any])
        let trustProperties = try XCTUnwrap(trust["properties"] as? [String: Any])
        let trustLevel = try XCTUnwrap(trustProperties["level"] as? [String: Any])
        XCTAssertEqual(trustLevel["enum"] as? [String], ["trusted", "untrusted"])
        let approvedCommands = try XCTUnwrap(trustProperties["approved_commands"] as? [String: Any])
        let approvedCommandNames = try XCTUnwrap(approvedCommands["propertyNames"] as? [String: Any])
        XCTAssertEqual(approvedCommandNames["enum"] as? [String], ["check.cmd", "latest.cmd", "update.cmd"])
        let approvedCommandValue = try XCTUnwrap(approvedCommands["additionalProperties"] as? [String: Any])
        XCTAssertEqual(approvedCommandValue["minLength"] as? Int, 71)
        XCTAssertEqual(approvedCommandValue["maxLength"] as? Int, 71)
        XCTAssertEqual(approvedCommandValue["pattern"] as? String, "^sha256:[a-f0-9]{64}$")
        let check = try XCTUnwrap(properties["check"] as? [String: Any])
        let checkVariants = try XCTUnwrap(check["oneOf"] as? [[String: Any]])
        XCTAssertTrue(checkVariants.contains { variant in
            (variant["required"] as? [String]) == ["file"]
        })
        XCTAssertFalse(result.stdout.contains(#""query""#))
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
        XCTAssertFalse(result.stdout.contains("update, enabled, notify, trust"))
        XCTAssertFalse(result.stdout.contains("notify"))
        XCTAssertFalse(result.stdout.contains("jq"))
        XCTAssertTrue(result.stdout.contains("Defaults: enabled=true, update.requires_write=true"))
        XCTAssertTrue(result.stdout.contains("Literal API keys and token values are rejected"))
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

    func testTemplateRecipeRejectsSecretLikeOverridesWithoutEchoingThem() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-template-tests")
        let secret = "sk-or-v1-secret-value"

        let result = try CLIProcess.run(
            ["template", "recipe", "--kind", "npm", "--id", secret, "--name", "Tool \(secret)", "--source", secret],
            home: home
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("template override must not contain literal secrets"))
        XCTAssertFalse(result.stderr.contains(secret))
    }

    func testTemplateRecipeRejectsInvalidIDOverride() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-template-tests")

        let result = try CLIProcess.run(
            ["template", "recipe", "--kind", "npm", "--id", "Bad Tool"],
            home: home
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("template --id must match"))
    }

    func testTemplateRecipeShellQuotesSourceOverridesInGeneratedCommands() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-template-tests")
        let source = "pkg'; touch /tmp/pwn #"

        let result = try CLIProcess.run(
            ["template", "recipe", "--kind", "npm", "--id", "tool", "--source", source],
            home: home
        )

        XCTAssertEqual(result.exitCode, 0)
        let recipe = try JSONDecoder.updateBar.decode(Recipe.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(recipe.source.ref, source)
        XCTAssertEqual(recipe.update.cmd, "npm install -g 'pkg'\\''; touch /tmp/pwn #'@latest")
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

    func testTemplateManifestRejectsSecretLikeOverridesWithoutEchoingThem() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-template-tests")
        let secret = "sk-or-v1-secret-value"

        let result = try CLIProcess.run(
            ["template", "manifest", "--kind", "npm", "--source", secret],
            home: home
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("template override must not contain literal secrets"))
        XCTAssertFalse(result.stderr.contains(secret))
    }

    private func schemaRecipeDefinition(from root: [String: Any]?) throws -> [String: Any] {
        let defs = try XCTUnwrap(root?["$defs"] as? [String: Any])
        return try XCTUnwrap(defs["recipe"] as? [String: Any])
    }

    private func boolDefault(in properties: [String: Any], _ key: String, nestedIn parentKey: String? = nil) throws -> Bool {
        let targetProperties: [String: Any]
        if let parentKey {
            let parent = try XCTUnwrap(properties[parentKey] as? [String: Any])
            targetProperties = try XCTUnwrap(parent["properties"] as? [String: Any])
        } else {
            targetProperties = properties
        }
        let property = try XCTUnwrap(targetProperties[key] as? [String: Any])
        return try XCTUnwrap(property["default"] as? Bool)
    }
}
