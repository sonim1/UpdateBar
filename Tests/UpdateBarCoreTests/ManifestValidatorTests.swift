import XCTest
import UpdateBarCore
import UpdateBarTestSupport

final class ManifestValidatorTests: XCTestCase {
    func testAcceptsValidManifest() throws {
        let result = try ManifestValidator.validate(data: data("valid-basic.json"))
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.errors, [])
    }

    func testRejectsMissingRequiredFieldWithPath() throws {
        let result = try ManifestValidator.validate(data: data("invalid-missing-required.json"))
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains("items[0].name: required"))
    }

    func testRejectsDuplicateIds() throws {
        var manifest = try loadValid()
        manifest.items.append(manifest.items[0])
        let encoded = try JSONEncoder.updateBar.encode(manifest)

        let result = try ManifestValidator.validate(data: encoded)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains("items[1].id: duplicate id claude-code"))
    }

    func testRejectsInvalidEnumsAndStrategyRequirements() throws {
        let json = """
        {
          "schema_version": 1,
          "items": [
            {
              "id": "bad id",
              "name": "Bad",
              "category": "cli",
              "source": { "kind": "wat", "ref": "x", "branch": null },
              "version_scheme": "magic",
              "check": { "cmd": "bad --version" },
              "latest": { "strategy": "cmd", "cmd": null, "pattern": null },
              "version_parse": { "regex": "x", "jq": ".version" },
              "update": { "cmd": "bad update", "requires_write": true, "cwd": null },
              "pin": null,
              "enabled": true,
              "notify": true,
              "trust": { "level": "trusted", "approved_commands": {} },
              "sync": null
            }
          ],
          "provenance": {
            "created_by": "updatebar",
            "created_at": "2026-06-09T00:00:00Z",
            "updated_at": "2026-06-09T00:00:00Z"
          }
        }
        """.data(using: .utf8)!

        let result = try ManifestValidator.validate(data: json)

        XCTAssertTrue(result.errors.contains("items[0].id: must match ^[a-z0-9][a-z0-9._-]*$"))
        XCTAssertTrue(result.errors.contains("items[0].source.kind: unsupported value wat"))
        XCTAssertTrue(result.errors.contains("items[0].version_scheme: unsupported value magic"))
        XCTAssertTrue(result.errors.contains("items[0].latest.cmd: required when latest.strategy is cmd"))
        XCTAssertTrue(result.errors.contains("items[0].version_parse: exactly one of regex or jq is required"))
        XCTAssertTrue(result.errors.contains("items[0].sync: unsupported in schema_version 1"))
    }

    func testRejectsHttpRegexWithoutPattern() throws {
        var manifest = try loadValid()
        manifest.items[0].latest.strategy = .httpRegex
        manifest.items[0].latest.pattern = nil
        let result = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains("items[0].latest.pattern: required when latest.strategy is http_regex"))
    }

    func testRejectsJQVersionParseUntilRuntimeSupportExists() throws {
        var manifest = try loadValid()
        manifest.items[0].versionParse = .jq(".version")

        let result = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains("items[0].version_parse.jq: unsupported until runtime support is implemented"))
    }

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: TestFixtures.fixtureURL("manifests", name))
    }

    private func loadValid() throws -> Manifest {
        try JSONDecoder.updateBar.decode(Manifest.self, from: data("valid-basic.json"))
    }
}
