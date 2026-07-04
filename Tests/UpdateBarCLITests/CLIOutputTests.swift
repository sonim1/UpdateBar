import XCTest
import UpdateBarCore
import UpdateBarTestSupport

final class CLIOutputTests: XCTestCase {
    func testInvalidArgsReturnUserErrorExitCode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("not-a-command"))
    }

    func testUnknownCommandHelpReturnsUserError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--help"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("not-a-command"))
        XCTAssertTrue(result.stderr.contains("updatebar --help"))
    }

    func testUnknownCommandVersionReturnsUserError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--version"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("not-a-command"))
        XCTAssertTrue(result.stderr.contains("updatebar --help"))
    }

    func testHelpUnknownCommandReturnsUserError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["help", "not-a-command"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("not-a-command"))
        XCTAssertTrue(result.stderr.contains("updatebar help"))
    }

    func testHelpRejectsExtraPathAfterLeafCommand() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["help", "status", "extra"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("extra"))
        XCTAssertTrue(result.stderr.contains("status"))
    }

    func testRootHelpRejectsTrailingCommandTarget() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["--help", "status"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("status"))
        XCTAssertTrue(result.stderr.contains("updatebar help status"))
    }

    func testInlineHelpRejectsTrailingArgument() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["status", "--help", "extra"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("extra"))
        XCTAssertTrue(result.stderr.contains("updatebar status --help"))
    }

    func testRootHelpRejectsTrailingOption() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["--help", "--force"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("--force"))
        XCTAssertTrue(result.stderr.contains("updatebar --help"))
        XCTAssertFalse(result.stderr.contains("updatebar help --force"))
    }

    func testRootVersionRejectsTrailingCommandTarget() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["--version", "status"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("status"))
        XCTAssertTrue(result.stderr.contains("updatebar --version"))
    }

    func testInlineVersionRejectsTrailingArgument() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["status", "--version", "extra"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("extra"))
        XCTAssertTrue(result.stderr.contains("updatebar status --version"))
    }

    func testInlineVersionRejectsTrailingOption() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["status", "--version", "--force"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("--force"))
        XCTAssertTrue(result.stderr.contains("updatebar status --version"))
    }

    func testHelpVersionRejectsTrailingArgument() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["help", "--version", "extra"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("extra"))
        XCTAssertTrue(result.stderr.contains("updatebar --version"))
    }

    func testUnknownCommandWithJSONDoesNotExposeEnvironmentSecret() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")
        let secret = "sk-or-v1-super-secret-value"

        let result = try CLIProcess.run(
            ["not-a-command", "--json"],
            home: home,
            environment: ["OPENROUTER_API_KEY": secret]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.stdout.contains(secret))
        XCTAssertFalse(result.stderr.contains(secret))
    }

    func testUpdateCommandJSONDoesNotExposeFailedCommandSecret() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")
        let secret = "sk-or-v1-super-secret-value"
        let paths = AppPaths(homeDirectory: home)
        var recipe = Recipe(
            id: "tool",
            name: "Tool",
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: "tool", branch: nil),
            versionScheme: .semver,
            check: .command("printf 'tool 1.0.0'"),
            latest: LatestSpec(strategy: .cmd, cmd: "printf 'tool 1.1.0'", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "printf '%s%s' 'sk-or-v1-' 'super-secret-value' >&2; exit 3", cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &recipe)
        try ManifestStore(paths: paths).save(manifest([recipe]))
        try StateStore(paths: paths).save(
            State(schemaVersion: 1, generatedAt: Date(timeIntervalSince1970: 1_800), items: [
                "tool": itemState(status: .outdated, current: "1.0.0", latest: "1.1.0")
            ])
        )

        let result = try CLIProcess.run(["update", "tool", "--yes", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 2)
        let results = try JSONDecoder.updateBar.decode([UpdateResult].self, from: Data(result.stdout.utf8))
        XCTAssertEqual(results.map(\.outcome), [.failed])
        XCTAssertFalse(result.stdout.contains(secret))
        XCTAssertFalse(results.first?.error?.contains(secret) ?? false)
    }

    private func manifest(_ items: [Recipe]) -> Manifest {
        Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: Date(timeIntervalSince1970: 1_800), updatedAt: Date(timeIntervalSince1970: 1_800))
        )
    }

    private func itemState(status: ItemStatus, current: String, latest: String) -> ItemState {
        ItemState(
            current: current,
            latest: latest,
            status: status,
            lastChecked: Date(timeIntervalSince1970: 1_800),
            error: nil,
            backoffUntil: nil
        )
    }

    func testValidateInvalidManifestJSONStaysMachineReadable() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")
        let fixture = TestFixtures.fixtureURL("manifests", "invalid-missing-required.json")

        let result = try CLIProcess.run(["validate", fixture.path, "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ValidationPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.valid)
        XCTAssertFalse(payload.errors.isEmpty)
    }

    func testVersionJSONMatchesVersionEnv() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")
        let versionEnv = try String(contentsOfFile: "version.env", encoding: .utf8)
        let expected = try XCTUnwrap(versionEnv.split(separator: "\n").first { $0.hasPrefix("UPDATEBAR_VERSION=") })
            .replacingOccurrences(of: "UPDATEBAR_VERSION=", with: "")

        let result = try CLIProcess.run(["--version"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            expected
        )
    }

    func testChangelogHasCurrentVersionEntry() throws {
        let versionEnv = try String(contentsOfFile: "version.env", encoding: .utf8)
        let expected = try XCTUnwrap(versionEnv.split(separator: "\n").first { $0.hasPrefix("UPDATEBAR_VERSION=") })
            .replacingOccurrences(of: "UPDATEBAR_VERSION=", with: "")
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## \(expected)"))
    }

    func testChangelogUnreleasedDocumentsPostReleaseHardening() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)
        let unreleased = try changelogSection("Unreleased", in: changelog)

        XCTAssertTrue(unreleased.contains("release installer"))
        XCTAssertTrue(unreleased.contains("release archive extraction"))
        XCTAssertTrue(unreleased.contains("local installer"))
        XCTAssertTrue(unreleased.contains("app archive"))
        XCTAssertTrue(unreleased.contains("quality gate"))
        XCTAssertTrue(unreleased.contains("TUI subprocess"))
        XCTAssertTrue(unreleased.contains("abort listener"))
        XCTAssertTrue(unreleased.contains("explicit-any"))
    }

    func testUnknownCommandWithJSONReturnsErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains(where: { $0.contains("not-a-command") }))
        XCTAssertFalse(payload.errors.contains(where: { $0.contains("Unknown option '--json'") }))
    }

    func testUnknownCommandWithJSONEqualsReturnsErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--json=true"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains(where: { $0.contains("not-a-command") }))
        XCTAssertFalse(payload.errors.contains(where: { $0.contains("Unknown option '--json'") }))
    }

    func testUnknownCommandWithJSONEqualsFalseUsesHumanError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--json=false"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("not-a-command"))
        XCTAssertTrue(result.stderr.contains("updatebar --help"))
        XCTAssertFalse(result.stderr.contains(#""ok":false"#))
    }

    func testUnknownCommandWithJSONStreamEqualsReturnsErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--json-stream=true"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains(where: { $0.contains("not-a-command") }))
        XCTAssertFalse(payload.errors.contains(where: { $0.contains("Unknown option '--json-stream'") }))
    }

    func testApproveJSONWithoutIDReportsMissingIDBeforeFieldHint() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["approve", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let payload = try JSONDecoder.updateBar.decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains(where: { $0.contains("Missing expected argument '<id>'") }))
        XCTAssertFalse(payload.errors.contains(where: { $0.contains("approve requires --field") }))
    }

    func testStatusWithJSONEqualsParsesAsJSONMode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["status", "--json=true"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let snapshot = try JSONDecoder.updateBar.decode(StatusSnapshot.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(snapshot.summary.total, 0)
    }

    func testStatusWithJSONSpaceSeparatedTrueStillParses() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["status", "--json", "true"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let snapshot = try JSONDecoder.updateBar.decode(StatusSnapshot.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(snapshot.summary.total, 0)
    }

    func testStatusWithJSONSpaceSeparatedFalseFallsBackToHumanMode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["status", "--json", "false"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("\"generated_at\""))
        XCTAssertEqual(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, true)
    }

    func testStatusWithJSONEqualsFalseFallsBackToHumanMode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["status", "--json=false"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("\"generated_at\""))
        XCTAssertEqual(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, true)
    }

    func testStatusWithJSONStreamEqualsProducesErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["status", "--json-stream=true"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("status does not support JSONL streaming") })
        XCTAssertTrue(payload.errors.contains { $0.contains("Run updatebar status --json") })
    }

    func testScanWithJSONStreamEqualsProducesGuidance() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["scan", "--json-stream=true"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("scan does not support JSONL streaming") })
        XCTAssertTrue(payload.errors.contains { $0.contains("Run updatebar scan --json") })
    }

    func testInitWithJSONStreamEqualsProducesGuidance() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["init", "--json-stream=true"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("init does not support JSONL streaming") })
        XCTAssertTrue(payload.errors.contains { $0.contains("Run updatebar init --select all --json") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar scan --json") })
    }

    func testExportWithJSONStreamEqualsProducesGuidance() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["export", "--json-stream=true"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("export does not support JSONL streaming") })
        XCTAssertTrue(payload.errors.contains { $0.contains("Run updatebar export --json") })
    }

    func testCheckWithJSONEqualsParsesAsJSONMode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["check", "--json=true"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode([CheckResult].self, from: Data(result.stdout.utf8))
        XCTAssertTrue(payload.isEmpty)
    }

    func testCheckWithJSONStreamEqualsParsesAsJSONStreamMode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["check", "--json-stream=true"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("\"type\":\"started\""))
        XCTAssertTrue(result.stdout.contains("\"type\":\"finished\""))
    }

    func testUpdateWithJSONEqualsParsesAsJSONMode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["update", "--json=true"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let payload = try JSONDecoder.updateBar.decode([UpdateResult].self, from: Data(result.stdout.utf8))
        XCTAssertTrue(payload.isEmpty)
    }

    func testJSONErrorRedactsSecretLikePathFragments() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")
        let secret = "sk-or-v1-super-secret-value"

        let result = try CLIProcess.run(["validate", secret, "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains(where: { $0.contains("[REDACTED]") }))
        XCTAssertFalse(payload.errors.contains(where: { $0.contains(secret) }))
    }

    func testNonJSONErrorRedactsSecretLikePathFragments() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")
        let secret = "sk-or-v1-super-secret-value"

        let result = try CLIProcess.run(["validate", secret], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("[REDACTED]"))
        XCTAssertFalse(result.stderr.contains(secret))
    }

    func testRuntimeErrorWithJSONReturnsErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["config", "set", "missing.key", "value", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "config_error")
        XCTAssertTrue(payload.errors.first?.contains("missing.key") ?? false)
    }

    private struct ValidationPayload: Decodable {
        var valid: Bool
        var errors: [String]
    }

    private struct ErrorEnvelope: Decodable {
        var ok: Bool
        var code: String
        var errors: [String]
    }

    private func changelogSection(_ title: String, in changelog: String) throws -> String {
        let start = try XCTUnwrap(changelog.range(of: "## \(title)"))
        let remainder = changelog[start.upperBound...]
        let end = remainder.range(of: "\n## ")?.lowerBound ?? remainder.endIndex
        return String(remainder[..<end])
    }
}
