import XCTest

final class ListCommandTests: XCTestCase {
    func testListCommandIsRemovedFromCLI() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-list-tests")

        let result = try CLIProcess.run(["list"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Unexpected argument 'list'"))
    }
}
