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
            update: UpdateSpec(cmd: "printf '\(secret)' >&2; exit 3", cwd: nil),
            pin: nil,
            enabled: true,
            notify: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &recipe)
        try ManifestStore(paths: paths).save(manifest(items: [recipe]))
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

        let result = try CLIProcess.run(["version", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder().decode(VersionPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.version, expected)
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

    func testJSONErrorRedactsSecretLikePathFragments() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")
        let secret = "sk-or-v1-super-secret-value"

        let result = try CLIProcess.run(["validate", secret, "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "runtime_error")
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

    func testAddTrustRedactsCommandsPrintedToStderr() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")
        let secret = "sk-or-v1-trust-command-secret"
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
            update: UpdateSpec(cmd: "printf '\(secret)'", cwd: nil),
            pin: nil,
            enabled: true,
            notify: true,
            trust: Trust(level: .untrusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &recipe)

        let manifest = Manifest(
            schemaVersion: 1,
            items: [recipe],
            provenance: Provenance(createdBy: "test", createdAt: Date(), updatedAt: Date())
        )
        let file = home.appendingPathComponent("recipe.json")
        try JSONEncoder.updateBar.encode(manifest).write(to: file)

        let result = try CLIProcess.run(
            ["add", "--from", file.path, "--trust", "--yes"],
            home: home
        )

        XCTAssertEqual(result.exitCode, 0)
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

    private struct VersionPayload: Decodable {
        var version: String
    }

    private struct ErrorEnvelope: Decodable {
        var ok: Bool
        var code: String
        var errors: [String]
    }
}
