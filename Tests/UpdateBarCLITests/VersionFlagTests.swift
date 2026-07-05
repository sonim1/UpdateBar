import XCTest

final class VersionFlagTests: XCTestCase {
    func testRootVersionFlagPrintsVersion() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-version-tests")

        let result = try CLIProcess.run(["--version"], home: home)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        let pattern = #"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?"#
        XCTAssertTrue(
            output.range(of: pattern, options: .regularExpression) != nil,
            "version output: \(output)")
    }

    func testVersionCommandWasRemoved() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-version-tests")

        let result = try CLIProcess.run(["version"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("updatebar version was removed"))
        XCTAssertTrue(result.stderr.contains("Run updatebar --version"))
    }

    func testVersionCommandJSONWasRemoved() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-version-tests")

        let result = try CLIProcess.run(["version", "--json"], home: home)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar version was removed") })
        XCTAssertTrue(payload.errors.contains { $0.contains("Run updatebar --version") })
    }

    func testHelpVersionCommandPointsToVersionFlag() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-version-tests")

        let result = try CLIProcess.run(["help", "version"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("updatebar version was removed"))
        XCTAssertTrue(result.stderr.contains("Run updatebar --version"))
    }

    private struct ErrorEnvelope: Decodable {
        var code: String
        var errors: [String]
    }
}
