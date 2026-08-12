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

    func testSettingsAndAboutUseReadableFooterTitles() {
        XCTAssertEqual(MenuBarMenuAction.openConfig.title, "Settings...")
        XCTAssertEqual(MenuBarMenuAction.about.title, "About UpdateBar")
    }

    func testMenuBarHidesTUIAndViewLogsActions() {
        XCTAssertFalse(MenuBarMenuAction.footer.contains(.openTUI))
        XCTAssertFalse(MenuBarMenuAction.footer.contains(.viewLogs))
        XCTAssertFalse(MenuBarMenuAction.errorRecovery.contains(.openTUI))
        XCTAssertFalse(MenuBarMenuAction.errorRecovery.contains(.viewLogs))
    }

    func testErrorRecoveryActionsKeepDashboardNavigation() {
        XCTAssertEqual(
            MenuBarMenuAction.errorRecovery.map(\.title),
            [
                "Refresh Status",
                "Check Now",
                "Dashboard",
                "Check for Updates...",
                "Quit",
            ])
    }
}
