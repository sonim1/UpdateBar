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

    func testRejectsItemsValueThatIsNotAnArray() throws {
        var manifest = try loadValidJSONObject()
        manifest["items"] = "not an array"

        let result = try ManifestValidator.validate(data: JSONSerialization.data(withJSONObject: manifest))

        XCTAssertTrue(result.errors.contains("items: must be an array"))
        XCTAssertFalse(result.errors.contains("items: required"))
    }

    func testRejectsItemsArrayEntriesThatAreNotObjects() throws {
        var manifest = try loadValidJSONObject()
        var item = try XCTUnwrap((manifest["items"] as? [[String: Any]])?.first)
        item.removeValue(forKey: "name")
        manifest["items"] = ["not an object", item] as [Any]

        let result = try ManifestValidator.validate(data: JSONSerialization.data(withJSONObject: manifest))

        XCTAssertTrue(result.errors.contains("items[0]: must be an object"))
        XCTAssertTrue(result.errors.contains("items[1].name: required"))
    }

    func testRejectsWhitespaceOnlyRequiredStrings() throws {
        var manifest = try loadValid()
        manifest.items[0].name = " \t\n"

        let result = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertTrue(result.errors.contains("items[0].name: required"))
    }

    func testRejectsWhitespaceOnlyCheckCommand() throws {
        var manifest = try loadValid()
        manifest.items[0].check = .command(" \t\n")

        let result = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertTrue(result.errors.contains("items[0].check: exactly one of cmd or file/query is required"))
    }

    func testRejectsWhitespaceOnlyCheckFileQuery() throws {
        var manifest = try loadValid()
        manifest.items[0].check = .file(path: " \t\n", query: "$.version")

        let blankPath = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertTrue(blankPath.errors.contains("items[0].check: exactly one of cmd or file/query is required"))

        manifest.items[0].check = .file(path: "/tmp/version.json", query: " \t\n")

        let blankQuery = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertTrue(blankQuery.errors.contains("items[0].check: exactly one of cmd or file/query is required"))
    }

    func testRejectsCheckWithCommandAndBlankFileQueryFields() throws {
        let result = try validateFirstRawItem {
            $0["check"] = [
                "cmd": "claude --version",
                "file": " \t\n",
                "query": " \t\n",
            ] as [String: Any]
        }

        XCTAssertTrue(result.errors.contains("items[0].check: exactly one of cmd or file/query is required"))
    }

    func testRejectsDuplicateIds() throws {
        var manifest = try loadValid()
        manifest.items.append(manifest.items[0])
        let encoded = try JSONEncoder.updateBar.encode(manifest)

        let result = try ManifestValidator.validate(data: encoded)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains("items[1].id: duplicate id claude-code"))
    }

    func testRejectsIDsWithTrailingNewlines() throws {
        var manifest = try loadValid()
        manifest.items[0].id = "claude-code\n"

        let result = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertTrue(result.errors.contains("items[0].id: must match ^[a-z0-9][a-z0-9._-]*$"))
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

    func testRejectsWhitespaceOnlyVersionRegex() throws {
        var manifest = try loadValid()
        manifest.items[0].versionParse = .regex(" \t\n")

        let result = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertTrue(result.errors.contains("items[0].version_parse: exactly one of regex or jq is required"))
    }

    func testRejectsVersionRegexWithBlankJQField() throws {
        let result = try validateFirstRawItem {
            $0["version_parse"] = [
                "regex": "([0-9]+\\.[0-9]+\\.[0-9]+)",
                "jq": " \t\n",
            ] as [String: Any]
        }

        XCTAssertTrue(result.errors.contains("items[0].version_parse: exactly one of regex or jq is required"))
    }

    func testDefaultsMissingUpdateRequiresWriteToTrue() throws {
        let data = try validDataUpdatingFirstRawItem {
            var update = try XCTUnwrap($0["update"] as? [String: Any])
            update.removeValue(forKey: "requires_write")
            $0["update"] = update
        }

        let result = try ManifestValidator.validate(data: data)

        XCTAssertTrue(result.isValid, result.errors.joined(separator: "\n"))

        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        XCTAssertTrue(manifest.items[0].update.requiresWrite)
    }

    func testRejectsNonBooleanUpdateRequiresWrite() throws {
        let result = try validateFirstRawItem {
            var update = try XCTUnwrap($0["update"] as? [String: Any])
            update["requires_write"] = NSNull()
            $0["update"] = update
        }

        XCTAssertTrue(result.errors.contains("items[0].update.requires_write: must be a boolean when provided"))
    }

    func testDefaultsMissingEnabledAndNotifyToTrue() throws {
        let data = try validDataUpdatingFirstRawItem {
            $0.removeValue(forKey: "enabled")
            $0.removeValue(forKey: "notify")
        }

        let result = try ManifestValidator.validate(data: data)

        XCTAssertTrue(result.isValid, result.errors.joined(separator: "\n"))

        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        XCTAssertTrue(manifest.items[0].enabled)
        XCTAssertTrue(manifest.items[0].notify)
    }

    func testRejectsNullOrNonBooleanEnabledAndNotify() throws {
        let result = try validateFirstRawItem {
            $0["enabled"] = NSNull()
            $0["notify"] = "true"
        }

        XCTAssertTrue(result.errors.contains("items[0].enabled: must be a boolean when provided"))
        XCTAssertTrue(result.errors.contains("items[0].notify: must be a boolean when provided"))
    }

    func testRejectsInvalidOptionalStringFieldTypes() throws {
        let result = try validateFirstRawItem {
            $0["path"] = 42
            $0["pin"] = true
            var source = try XCTUnwrap($0["source"] as? [String: Any])
            source["branch"] = false
            $0["source"] = source
            var latest = try XCTUnwrap($0["latest"] as? [String: Any])
            latest["cmd"] = ["bad"]
            latest["pattern"] = 123
            $0["latest"] = latest
            var update = try XCTUnwrap($0["update"] as? [String: Any])
            update["cwd"] = ["bad": true]
            $0["update"] = update
        }

        XCTAssertTrue(result.errors.contains("items[0].path: must be a string or null when provided"))
        XCTAssertTrue(result.errors.contains("items[0].pin: must be a string or null when provided"))
        XCTAssertTrue(result.errors.contains("items[0].source.branch: must be a string or null when provided"))
        XCTAssertTrue(result.errors.contains("items[0].latest.cmd: must be a string or null when provided"))
        XCTAssertTrue(result.errors.contains("items[0].latest.pattern: must be a string or null when provided"))
        XCTAssertTrue(result.errors.contains("items[0].update.cwd: must be a string or null when provided"))
    }

    func testRejectsNonStringApprovedCommandFingerprints() throws {
        let result = try validateFirstRawItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["approved_commands"] = [
                "check.cmd": true,
                "update.cmd": NSNull(),
            ] as [String: Any]
            $0["trust"] = trust
        }

        XCTAssertTrue(result.errors.contains("items[0].trust.approved_commands[check.cmd]: must be a string"))
        XCTAssertTrue(result.errors.contains("items[0].trust.approved_commands[update.cmd]: must be a string"))
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

    private func validateFirstRawItem(_ update: (inout [String: Any]) throws -> Void) throws -> ValidationResult {
        try ManifestValidator.validate(data: validDataUpdatingFirstRawItem(update))
    }

    private func validDataUpdatingFirstRawItem(_ update: (inout [String: Any]) throws -> Void) throws -> Data {
        var manifest = try loadValidJSONObject()
        var items = try XCTUnwrap(manifest["items"] as? [[String: Any]])
        var item = try XCTUnwrap(items.first)
        try update(&item)
        items[0] = item
        manifest["items"] = items

        return try JSONSerialization.data(withJSONObject: manifest)
    }

    private func loadValidJSONObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data("valid-basic.json"))
        return try XCTUnwrap(object as? [String: Any])
    }
}
