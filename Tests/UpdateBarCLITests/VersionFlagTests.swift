import XCTest

final class VersionFlagTests: XCTestCase {
    func testRootVersionFlagPrintsVersion() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-version-tests")

        let result = try CLIProcess.run(["--version"], home: home)
        let output = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(output.contains(UpdateBarVersion.current), "version output: \(output)")
    }

    func testVersionCommandWasRemoved() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-version-tests")

        let result = try CLIProcess.run(["version"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue((result.stdout + result.stderr).contains("Unexpected argument 'version'"))
    }
}
