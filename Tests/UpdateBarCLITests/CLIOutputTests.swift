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

    func testRemovedAuthCommandDoesNotExposeEnvironmentSecret() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")
        let secret = "sk-or-v1-super-secret-value"

        let result = try CLIProcess.run(
            ["auth", "status", "--json"],
            home: home,
            environment: ["OPENROUTER_API_KEY": secret]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.stdout.contains(secret))
        XCTAssertFalse(result.stderr.contains(secret))
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

    func testUnknownCommandWithJSONReturnsErrorEnvelope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-output-tests")

        let result = try CLIProcess.run(["not-a-command", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertFalse(payload.errors.isEmpty)
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
