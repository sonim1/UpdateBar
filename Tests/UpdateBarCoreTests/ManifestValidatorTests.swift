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

    func testRejectsSchemaVersionWithWrongType() throws {
        var manifest = try loadValidJSONObject()
        manifest["schema_version"] = "1"

        let result = try ManifestValidator.validate(data: JSONSerialization.data(withJSONObject: manifest))

        XCTAssertTrue(result.errors.contains("schema_version: must be integer 1"))
        XCTAssertFalse(result.errors.contains("schema_version: required"))

        manifest["schema_version"] = true

        let booleanResult = try ManifestValidator.validate(data: JSONSerialization.data(withJSONObject: manifest))

        XCTAssertTrue(booleanResult.errors.contains("schema_version: must be integer 1"))
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

    func testRejectsMissingOrNonObjectProvenance() throws {
        var missingProvenance = try loadValidJSONObject()
        missingProvenance.removeValue(forKey: "provenance")

        let missingResult = try ManifestValidator.validate(data: JSONSerialization.data(withJSONObject: missingProvenance))

        XCTAssertTrue(missingResult.errors.contains("provenance: required"))

        var wrongTypeProvenance = try loadValidJSONObject()
        wrongTypeProvenance["provenance"] = "generated"

        let wrongTypeResult = try ManifestValidator.validate(data: JSONSerialization.data(withJSONObject: wrongTypeProvenance))

        XCTAssertTrue(wrongTypeResult.errors.contains("provenance: must be an object"))
    }

    func testRejectsInvalidProvenanceFields() throws {
        var manifest = try loadValidJSONObject()
        manifest["provenance"] = [
            "created_by": " \t\n",
            "created_at": "not a date",
            "updated_at": 42,
        ] as [String: Any]

        let result = try ManifestValidator.validate(data: JSONSerialization.data(withJSONObject: manifest))

        XCTAssertTrue(result.errors.contains("provenance.created_by: required"))
        XCTAssertTrue(result.errors.contains("provenance.created_at: must be an ISO-8601 date string"))
        XCTAssertTrue(result.errors.contains("provenance.updated_at: must be an ISO-8601 date string"))
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

        XCTAssertTrue(result.errors.contains("items[0].check: exactly one of cmd or file is required"))
    }

    func testAcceptsCheckFileWithoutUnusedQuery() throws {
        let data = try validDataUpdatingFirstRawItem {
            $0["check"] = ["file": "/tmp/version.txt"]
        }

        let result = try ManifestValidator.validate(data: data)

        XCTAssertTrue(result.isValid, result.errors.joined(separator: "\n"))
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        guard case let .file(path) = manifest.items[0].check else {
            return XCTFail("expected check.file")
        }
        XCTAssertEqual(path, "/tmp/version.txt")
    }

    func testRejectsUnsupportedCheckFileQuery() throws {
        let result = try validateFirstRawItem {
            $0["check"] = [
                "file": "/tmp/version.json",
                "query": "$.version",
            ] as [String: Any]
        }

        XCTAssertTrue(result.errors.contains("items[0].check.query: unsupported until runtime support is implemented"))
    }

    func testRejectsWhitespaceOnlyCheckFile() throws {
        var manifest = try loadValid()
        manifest.items[0].check = .file(path: " \t\n")

        let blankPath = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertTrue(blankPath.errors.contains("items[0].check: exactly one of cmd or file is required"))
    }

    func testRejectsCheckWithCommandAndBlankFileQueryFields() throws {
        let result = try validateFirstRawItem {
            $0["check"] = [
                "cmd": "claude --version",
                "file": " \t\n",
                "query": " \t\n",
            ] as [String: Any]
        }

        XCTAssertTrue(result.errors.contains("items[0].check: exactly one of cmd or file is required"))
    }

    func testRejectsDuplicateIds() throws {
        var manifest = try loadValid()
        manifest.items.append(manifest.items[0])
        let encoded = try JSONEncoder.updateBar.encode(manifest)

        let result = try ManifestValidator.validate(data: encoded)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains("items[1].id: duplicate id claude-code"))
    }

    func testRejectsDuplicateSecretLikeIDsWithoutLeakingValue() throws {
        let secret = "sk-or-v1-secret-value"
        var manifest = try loadValid()
        manifest.items[0].id = secret
        manifest.items.append(manifest.items[0])

        let result = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains("items[0].id: duplicate id [REDACTED]"))
        XCTAssertTrue(result.errors.contains("items[1].id: duplicate id [REDACTED]"))
        XCTAssertFalse(result.errors.joined(separator: "\n").contains(secret))
    }

    func testRejectsIDsWithTrailingNewlines() throws {
        var manifest = try loadValid()
        manifest.items[0].id = "claude-code\n"

        let result = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))

        XCTAssertTrue(result.errors.contains("items[0].id: must match ^[a-z0-9][a-z0-9._-]*$"))
    }

    func testRejectsStoredElevatedTrustLevel() throws {
        let result = try validateFirstRawItem { item in
            var trust = try XCTUnwrap(item["trust"] as? [String: Any])
            trust["level"] = "elevated"
            item["trust"] = trust
        }

        XCTAssertTrue(result.errors.contains("items[0].trust.level: unsupported value elevated"))
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

    func testRedactsSecretLikeUnsupportedEnumValues() throws {
        let secret = "sk-or-v1-secret-value"
        let result = try validateFirstRawItem {
            $0["source"] = [
                "kind": secret,
                "ref": "@anthropic-ai/claude-code",
                "branch": NSNull(),
            ] as [String: Any]
            $0["version_scheme"] = secret
            $0["latest"] = [
                "strategy": secret,
                "cmd": NSNull(),
                "pattern": NSNull(),
            ] as [String: Any]
            $0["trust"] = [
                "level": secret,
                "approved_commands": [:],
            ] as [String: Any]
        }

        XCTAssertTrue(result.errors.contains("items[0].source.kind: unsupported value [REDACTED]"))
        XCTAssertTrue(result.errors.contains("items[0].version_scheme: unsupported value [REDACTED]"))
        XCTAssertTrue(result.errors.contains("items[0].latest.strategy: unsupported value [REDACTED]"))
        XCTAssertTrue(result.errors.contains("items[0].trust.level: unsupported value [REDACTED]"))
        XCTAssertFalse(result.errors.joined(separator: "\n").contains(secret))
    }

    func testRejectsMalformedGitHubReleaseSourceRefs() throws {
        let ownerOnly = try validateFirstRawItem {
            $0["source"] = ["kind": "github_release", "ref": "owner"]
            $0["latest"] = ["strategy": "github_release"]
        }
        let incompleteURL = try validateFirstRawItem {
            $0["source"] = ["kind": "github_release", "ref": "https://github.com/owner"]
            $0["latest"] = ["strategy": "github_release"]
        }

        XCTAssertTrue(
            ownerOnly.errors.contains("items[0].source.ref: invalid GitHub repository ref")
        )
        XCTAssertTrue(
            incompleteURL.errors.contains("items[0].source.ref: invalid GitHub repository ref")
        )
    }

    func testRejectsLatestStrategyThatDoesNotMatchSourceKind() throws {
        let result = try validateFirstRawItem {
            $0["source"] = ["kind": "npm", "ref": "left-pad"]
            $0["latest"] = ["strategy": "github_release"]
        }

        XCTAssertTrue(
            result.errors.contains(
                "items[0].latest.strategy: github_release requires source.kind github_release"
            )
        )
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

    func testRejectsVersionRegexRuntimeCannotExecute() throws {
        let invalidSyntax = try validateFirstRawItem {
            $0["version_parse"] = ["regex": "([0-9]+"]
        }
        let noCapture = try validateFirstRawItem {
            $0["version_parse"] = ["regex": "[0-9]+\\.[0-9]+\\.[0-9]+"]
        }
        let tooManyCaptures = try validateFirstRawItem {
            $0["version_parse"] = ["regex": "([0-9]+)\\.([0-9]+)"]
        }

        let expected = "items[0].version_parse.regex: invalid; expected exactly one capture group"
        XCTAssertTrue(invalidSyntax.errors.contains(expected))
        XCTAssertTrue(noCapture.errors.contains(expected))
        XCTAssertTrue(tooManyCaptures.errors.contains(expected))
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

    func testRejectsLiteralSecretsInExecutableFields() throws {
        let result = try validateFirstRawItem {
            $0["check"] = [
                "cmd": "OPENROUTER_API_KEY=sk-or-v1-secret-value tool --version",
            ] as [String: Any]
            $0["latest"] = [
                "strategy": "cmd",
                "cmd": "printf sk-or-v1-secret-value",
            ] as [String: Any]
            var update = try XCTUnwrap($0["update"] as? [String: Any])
            update["cmd"] = "tool update --token ghp_1234567890abcdefghijklmnopqrstu"
            update["cwd"] = "/tmp/sk-or-v1-secret-value"
            $0["update"] = update
        }

        XCTAssertTrue(result.errors.contains("items[0].check.cmd: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].latest.cmd: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].update.cmd: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].update.cwd: must not contain literal secrets"))
    }

    func testRejectsPackageManagerAndCloudTokenNamesInExecutableFields() throws {
        let result = try validateFirstRawItem {
            $0["check"] = [
                "cmd": "NPM_TOKEN=npm-secret tool --version",
            ] as [String: Any]
            $0["latest"] = [
                "strategy": "cmd",
                "cmd": "HOMEBREW_GITHUB_API_TOKEN=brew-secret brew livecheck tool",
            ] as [String: Any]
            var update = try XCTUnwrap($0["update"] as? [String: Any])
            update["cmd"] = "AWS_SECRET_ACCESS_KEY=aws-secret tool update"
            $0["update"] = update
        }

        XCTAssertTrue(result.errors.contains("items[0].check.cmd: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].latest.cmd: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].update.cmd: must not contain literal secrets"))
    }

    func testRejectsLiteralSecretsInStoredMetadataFields() throws {
        let result = try validateFirstRawItem {
            $0["id"] = "sk-or-v1-secret-value"
            $0["name"] = "Tool sk-or-v1-secret-value"
            $0["category"] = "sk-or-v1-secret-value"
            $0["path"] = "/tmp/sk-or-v1-secret-value"
            $0["source"] = [
                "kind": "git",
                "ref": "https://ghp_1234567890abcdefghijklmnopqrstu@github.com/owner/repo.git",
            ] as [String: Any]
            $0["check"] = [
                "file": "/tmp/NPM_TOKEN=npm-secret",
            ] as [String: Any]
            $0["latest"] = [
                "strategy": "git_tags",
            ] as [String: Any]
        }

        XCTAssertTrue(result.errors.contains("items[0].id: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].name: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].category: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].path: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].source.ref: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].check.file: must not contain literal secrets"))
    }

    func testRejectsLiteralSecretsInRemainingStoredRecipeFields() throws {
        let result = try validateFirstRawItem {
            $0["pin"] = "sk-or-v1-secret-value"
            $0["source"] = [
                "kind": "npm",
                "ref": "@anthropic-ai/claude-code",
                "branch": "sk-or-v1-secret-value",
            ] as [String: Any]
            $0["latest"] = [
                "strategy": "npm_registry",
                "cmd": NSNull(),
                "pattern": "sk-or-v1-secret-value",
            ] as [String: Any]
            $0["version_parse"] = ["regex": "(sk-or-v1-secret-value)"]
        }

        XCTAssertTrue(result.errors.contains("items[0].pin: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].source.branch: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].latest.pattern: must not contain literal secrets"))
        XCTAssertTrue(result.errors.contains("items[0].version_parse.regex: must not contain literal secrets"))
        XCTAssertFalse(result.errors.joined(separator: "\n").contains("sk-or-v1-secret-value"))
    }

    func testDefaultsMissingEnabledAndAcceptsMissingLegacyNotify() throws {
        let data = try validDataUpdatingFirstRawItem {
            $0.removeValue(forKey: "enabled")
            $0.removeValue(forKey: "notify")
        }

        let result = try ManifestValidator.validate(data: data)

        XCTAssertTrue(result.isValid, result.errors.joined(separator: "\n"))

        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        XCTAssertTrue(manifest.items[0].enabled)
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
            $0["check"] = [
                "file": "/tmp/version.txt",
                "query": 42,
            ] as [String: Any]
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
        XCTAssertTrue(result.errors.contains("items[0].check.query: must be a string or null when provided"))
        XCTAssertTrue(result.errors.contains("items[0].latest.cmd: must be a string or null when provided"))
        XCTAssertTrue(result.errors.contains("items[0].latest.pattern: must be a string or null when provided"))
        XCTAssertTrue(result.errors.contains("items[0].update.cwd: must be a string or null when provided"))
    }

    func testRejectsInvalidRequiredStringFieldTypesWithActionableMessages() throws {
        let result = try validateFirstRawItem {
            $0["id"] = 42
            var source = try XCTUnwrap($0["source"] as? [String: Any])
            source["kind"] = false
            $0["source"] = source
            var update = try XCTUnwrap($0["update"] as? [String: Any])
            update["cmd"] = ["bad"]
            $0["update"] = update
        }

        XCTAssertTrue(result.errors.contains("items[0].id: must be a string"))
        XCTAssertTrue(result.errors.contains("items[0].source.kind: must be a string"))
        XCTAssertTrue(result.errors.contains("items[0].update.cmd: must be a string"))
        XCTAssertFalse(result.errors.contains("items[0].id: required"))
        XCTAssertFalse(result.errors.contains("items[0].source.kind: required"))
        XCTAssertFalse(result.errors.contains("items[0].update.cmd: required"))
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

    func testRedactsSecretLikeApprovedCommandFieldNames() throws {
        let secret = "sk-or-v1-secret-value"
        let result = try validateFirstRawItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["approved_commands"] = [
                secret: true,
            ] as [String: Any]
            $0["trust"] = trust
        }

        XCTAssertTrue(result.errors.contains("items[0].trust.approved_commands[[REDACTED]]: must be a string"))
        XCTAssertFalse(result.errors.joined(separator: "\n").contains(secret))
    }

    func testRejectsSecretLikeApprovedCommandFingerprints() throws {
        let secret = "sk-or-v1-secret-value"
        let result = try validateFirstRawItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["approved_commands"] = [
                "update.cmd": secret,
            ] as [String: Any]
            $0["trust"] = trust
        }

        XCTAssertTrue(
            result.errors.contains("items[0].trust.approved_commands[update.cmd]: must not contain literal secrets")
        )
        XCTAssertFalse(result.errors.joined(separator: "\n").contains(secret))
    }

    func testRejectsMalformedApprovedCommandFingerprints() throws {
        let result = try validateFirstRawItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["approved_commands"] = [
                "check.cmd": "abc123",
                "update.cmd": "sha256:\(String(repeating: "g", count: 64))",
            ] as [String: Any]
            $0["trust"] = trust
        }

        XCTAssertTrue(
            result.errors.contains("items[0].trust.approved_commands[check.cmd]: must be a SHA-256 fingerprint")
        )
        XCTAssertTrue(
            result.errors.contains("items[0].trust.approved_commands[update.cmd]: must be a SHA-256 fingerprint")
        )
    }

    func testAcceptsSHA256ApprovedCommandFingerprints() throws {
        let result = try validateFirstRawItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["approved_commands"] = [
                "update.cmd": "sha256:\(String(repeating: "a", count: 64))",
            ] as [String: Any]
            $0["trust"] = trust
        }

        XCTAssertFalse(result.errors.contains { $0.contains("approved_commands[update.cmd]") })
    }

    func testRejectsApprovedCommandsOnUntrustedRecipes() throws {
        let result = try validateFirstRawItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["level"] = "untrusted"
            trust["approved_commands"] = [
                "update.cmd": "sha256:\(String(repeating: "a", count: 64))",
            ] as [String: Any]
            $0["trust"] = trust
        }

        XCTAssertTrue(
            result.errors.contains("items[0].trust.approved_commands: must be empty when trust.level is untrusted")
        )
    }

    func testRejectsUnknownApprovedCommandFields() throws {
        let result = try validateFirstRawItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["approved_commands"] = [
                "install.cmd": "sha256:\(String(repeating: "a", count: 64))",
            ] as [String: Any]
            $0["trust"] = trust
        }

        XCTAssertTrue(
            result.errors.contains("items[0].trust.approved_commands[install.cmd]: unknown command field")
        )
    }

    func testRejectsApprovalForCommandFieldAbsentFromRecipe() throws {
        let result = try validateFirstRawItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["approved_commands"] = [
                "latest.cmd": "sha256:\(String(repeating: "a", count: 64))",
            ] as [String: Any]
            $0["trust"] = trust
        }

        XCTAssertTrue(
            result.errors.contains("items[0].trust.approved_commands[latest.cmd]: unknown command field")
        )
    }

    func testRejectsSecretLikeApprovedCommandFieldNames() throws {
        let secret = "sk-or-v1-secret-value"
        let result = try validateFirstRawItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["approved_commands"] = [
                secret: "abc123",
            ] as [String: Any]
            $0["trust"] = trust
        }

        XCTAssertTrue(
            result.errors.contains("items[0].trust.approved_commands[[REDACTED]]: must not contain literal secrets")
        )
        XCTAssertFalse(result.errors.joined(separator: "\n").contains(secret))
    }

    func testRejectsJQVersionParseUntilRuntimeSupportExists() throws {
        let result = try validateFirstRawItem {
            $0["version_parse"] = ["jq": ".version"]
        }

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
