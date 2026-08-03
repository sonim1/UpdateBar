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
        XCTAssertTrue(MenuBarMenuAction.footer.contains(.openConfig))
        XCTAssertTrue(MenuBarMenuAction.footer.contains(.about))
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
                "Settings...",
                "About UpdateBar",
                "View Logs",
                "Check for Updates...",
                "Quit",
            ])
    }
}
