import Foundation
import XCTest

final class ListCommandTests: XCTestCase {
    func testListCommandPointsToStatusRecovery() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-list-tests")

        let result = try CLIProcess.run(["list"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("updatebar list was removed"))
        XCTAssertTrue(result.stderr.contains("Run updatebar status to list registered item ids."))
    }

    func testListCommandJSONPointsToStatusRecovery() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-list-tests")

        let result = try CLIProcess.run(["list", "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar list was removed.") })
        XCTAssertTrue(
            payload.errors.contains {
                $0.contains("Run updatebar status to list registered item ids.")
            })
    }

    private struct ErrorEnvelope: Decodable {
        var code: String
        var errors: [String]
    }
}
