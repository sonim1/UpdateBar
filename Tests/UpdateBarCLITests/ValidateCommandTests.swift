import Foundation
import XCTest
import UpdateBarCore
import UpdateBarTestSupport

final class ValidateCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testValidateReadsRecipeFromStdin() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-validate-tests")
        let encoded = try JSONEncoder.updateBar.encode(recipe())

        let result = try CLIProcess.run(["validate", "-", "--json"], home: home, stdin: String(decoding: encoded, as: UTF8.self))

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder().decode(ValidationPayload.self, from: Data(result.stdout.utf8))
        XCTAssertTrue(payload.valid)
        XCTAssertEqual(payload.errors, [])
    }

    func testValidateEmptyStdinJSONReturnsDecodeError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-validate-tests")

        let result = try CLIProcess.run(["validate", "-", "--json"], home: home, stdin: "")
        let payload = try JSONDecoder.updateBar.decode(ErrorPayload.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "decode_error")
        XCTAssertTrue(payload.errors.contains("document is not valid JSON"))
    }

    func testValidateExplainRejectsUnsupportedJQVersionParse() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-validate-tests")
        let file = home.appendingPathComponent("jq-recipe.json")
        try Data(jqRecipeJSON().utf8).write(to: file)

        let result = try CLIProcess.run(["validate", file.path, "--json", "--explain"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("version_parse.jq"))
        XCTAssertTrue(result.stdout.contains("unsupported until runtime support is implemented"))
        XCTAssertFalse(result.stdout.contains("decoded by the schema"))
    }

    func testValidateExplainGuidesInvalidVersionRegex() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-validate-tests")
        var item = recipe()
        item.versionParse = .regex("[0-9]+\\.[0-9]+\\.[0-9]+")
        let file = home.appendingPathComponent("regex-recipe.json")
        try JSONEncoder.updateBar.encode(item).write(to: file)

        let result = try CLIProcess.run(["validate", file.path, "--json", "--explain"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ValidationPayload.self, from: Data(result.stdout.utf8))
        XCTAssertTrue(payload.errors.contains("$.version_parse.regex: invalid; expected exactly one capture group"))
        XCTAssertEqual(
            payload.explanations.first?.hint,
            "Use version_parse.regex with exactly one capture group around the version."
        )
    }

    func testValidateTreatsProvenanceOnlyObjectAsManifest() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-validate-tests")
        let file = home.appendingPathComponent("broken-manifest.json")
        try Data(
            """
            {
              "provenance": {
                "created_by": "updatebar",
                "created_at": "2026-06-09T00:00:00Z",
                "updated_at": "2026-06-09T00:00:00Z"
              }
            }
            """.utf8
        ).write(to: file)

        let result = try CLIProcess.run(["validate", file.path, "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("schema_version: required"))
        XCTAssertTrue(result.stdout.contains("items: required"))
        XCTAssertFalse(result.stdout.contains("CodingKeys"))
    }

    func testValidateRejectsMalformedRecipeWithValidationErrors() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-validate-tests")
        let file = home.appendingPathComponent("broken-recipe.json")
        try Data(
            """
            {
              "id": "tool"
            }
            """.utf8
        ).write(to: file)

        let result = try CLIProcess.run(["validate", file.path, "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("$.name: required"))
        XCTAssertTrue(result.stdout.contains("$.source: required"))
        XCTAssertFalse(result.stdout.contains("CodingKeys"))
    }

    func testValidateMissingInputFileJSONReturnsUsageError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-validate-tests")
        let file = home.appendingPathComponent("missing-document.json")

        let result = try CLIProcess.run(["validate", file.path, "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(ErrorPayload.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("missing-document.json") })
    }

    private func recipe() -> Recipe {
        Recipe(
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
            trust: Trust(level: .untrusted, approvedCommands: [:])
        )
    }

    private func jqRecipeJSON() -> String {
        """
        {
          "id": "tool",
          "name": "Tool",
          "category": "cli",
          "source": { "kind": "custom", "ref": "tool", "branch": null },
          "version_scheme": "semver",
          "check": { "cmd": "printf 'tool 1.0.0'" },
          "latest": { "strategy": "cmd", "cmd": "printf 'tool 1.1.0'", "pattern": null },
          "version_parse": { "jq": ".version" },
          "update": { "cmd": "printf updated", "requires_write": true, "cwd": null },
          "pin": null,
          "enabled": true,
          "trust": { "level": "untrusted", "approved_commands": {} }
        }
        """
    }

    private struct ValidationPayload: Decodable {
        var valid: Bool
        var errors: [String]
        var explanations: [ValidationExplanation]

        private enum CodingKeys: String, CodingKey {
            case valid
            case errors
            case explanations
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            valid = try container.decode(Bool.self, forKey: .valid)
            errors = try container.decode([String].self, forKey: .errors)
            explanations = try container.decodeIfPresent([ValidationExplanation].self, forKey: .explanations) ?? []
        }
    }

    private struct ValidationExplanation: Decodable {
        var hint: String
    }

    private struct ErrorPayload: Decodable {
        var code: String
        var errors: [String]
    }
}
