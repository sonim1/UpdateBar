import UpdateBarMenuBar
import XCTest

final class MenuBarMenuActionTests: XCTestCase {
    func testUpdateActionUsesShortConsistentTitle() {
        XCTAssertEqual(MenuBarMenuAction.updateAllApprovedOutdated.title, "Run Updates")
    }

    func testRunUpdatesConfirmationCopyDescribesScope() {
        let confirmation = MenuBarActionConfirmation.confirmation(for: .updateAllApprovedOutdated)

        XCTAssertEqual(confirmation?.title, "Run Updates?")
        XCTAssertEqual(
            confirmation?.message,
            "This runs update commands for approved outdated items."
        )
        XCTAssertEqual(confirmation?.confirmButton, "Run Updates")
        XCTAssertEqual(confirmation?.cancelButton, "Cancel")
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
