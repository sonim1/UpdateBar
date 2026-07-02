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
        TrustPolicy.approveAllCommands(in: &recipe)
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

    func testUnknownCommandWithJSONReturnsErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertFalse(payload.errors.isEmpty)
    }

    func testUnknownCommandWithJSONEqualsReturnsErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--json=true"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertFalse(payload.errors.isEmpty)
    }

    func testUnknownCommandWithJSONStreamEqualsReturnsErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--json-stream=true"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertFalse(payload.errors.isEmpty)
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
        XCTAssertFalse(payload.errors.isEmpty)
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
}
