import XCTest

final class CLIUpdateJobsTests: XCTestCase {
    func testUpdateAcceptsJobsOverride() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-jobs-tests")

        let result = try CLIProcess.run(["update", "--jobs", "2", "--yes", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[]")
    }

    func testUpdateRejectsJobsOutsideAllowedRange() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-jobs-tests")

        let result = try CLIProcess.run(["update", "--jobs", "0", "--yes"], home: home)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue((result.stdout + result.stderr).contains("--jobs must be between 1 and 8"))
    }
}
