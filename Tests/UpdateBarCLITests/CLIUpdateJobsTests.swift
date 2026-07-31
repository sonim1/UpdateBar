import UpdateBarCore
import XCTest

/// Guards the --jobs bounds, which mirror UpdateConfig.validRange.
final class CLIUpdateJobsTests: XCTestCase {
    func testValidRangeMatchesConfig() {
        XCTAssertEqual(UpdateConfig.validRange, 1...8)
    }

    func testConfigRejectsJobsValuesOutsideRange() {
        var config = Config.default
        XCTAssertThrowsError(try config.set("update.max_concurrent", value: "0"))
        XCTAssertThrowsError(try config.set("update.max_concurrent", value: "9"))
    }
}
