import UpdateBarMenuBar
import XCTest

final class MenuBarRefreshPolicyTests: XCTestCase {
    func testRefreshPreservesActiveActionProgressInsteadOfBlocking() {
        XCTAssertEqual(
            MenuBarRefreshPolicy.presentationMode(activeActionTitle: "Updating tool"),
            .preserveActionProgress
        )
        XCTAssertEqual(
            MenuBarRefreshPolicy.presentationMode(activeActionTitle: nil),
            .showLoading
        )
    }
}
