import UpdateBarMenuBar
import XCTest

final class MenuBarMenuActionTests: XCTestCase {
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
