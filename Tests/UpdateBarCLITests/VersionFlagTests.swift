import XCTest

final class VersionFlagTests: XCTestCase {
    func testRootVersionFlagPrintsVersion() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-version-tests")

        let result = try CLIProcess.run(["--version"], home: home)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        let pattern = #"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?"#
        XCTAssertTrue(output.range(of: pattern, options: .regularExpression) != nil, "version output: \(output)")
    }

    func testVersionCommandWasRemoved() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-version-tests")

        let result = try CLIProcess.run(["version"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue((result.stdout + result.stderr).contains("Unexpected argument 'version'"))
    }
}
