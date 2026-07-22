import UpdateBarMenuBar
import XCTest

final class MenuBarMenuActionTests: XCTestCase {
    func testUpdateActionUsesShortConsistentTitle() {
        XCTAssertEqual(MenuBarMenuAction.updateAllApprovedOutdated.title, "Update All")
        XCTAssertNil(
            MenuBarActionConfirmation.confirmation(for: .updateAllApprovedOutdated)
        )
    }

    func testRefreshStatusUsesExplicitTitle() {
        XCTAssertEqual(MenuBarMenuAction.refreshStatus.title, "Refresh Status")
        XCTAssertNil(MenuBarActionConfirmation.confirmation(for: .refreshStatus))
    }

    func testCheckForUpdatesUsesSparkleTitleAndPrecedesQuit() {
        XCTAssertEqual(MenuBarMenuAction.checkForUpdates.title, "Check for Updates...")
        XCTAssertEqual(MenuBarMenuAction.footer.suffix(2), [.checkForUpdates, .quit])
        XCTAssertEqual(MenuBarMenuAction.errorRecovery.suffix(2), [.checkForUpdates, .quit])
    }

    func testErrorRecoveryActionsIncludeDiagnostics() {
        XCTAssertEqual(
            MenuBarMenuAction.errorRecovery.map(\.title),
            [
                "Refresh Status",
                "Check Now",
                "Open TUI",
                "Dashboard",
                "Manage Items...",
                "Scan & Add",
                "Open Config",
                "View Logs",
                "Check for Updates...",
                "Quit",
            ])
    }
}
