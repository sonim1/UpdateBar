import UpdateBarMenuBar
import XCTest

final class MenuBarMenuActionTests: XCTestCase {
    func testUpdateActionUsesShortConsistentTitle() {
        XCTAssertEqual(MenuBarMenuAction.updateAllApprovedOutdated.title, "Run Updates")
    }

    func testErrorRecoveryActionsIncludeDiagnostics() {
        XCTAssertEqual(MenuBarMenuAction.errorRecovery.map(\.title), [
            "Check Now",
            "Open TUI",
            "Open Config",
            "View Logs",
            "Quit",
        ])
    }
}
