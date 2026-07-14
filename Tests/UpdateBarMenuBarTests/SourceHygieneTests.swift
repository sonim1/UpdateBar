import Foundation
import XCTest

final class SourceHygieneTests: XCTestCase {
    func testMenuBarAppDelegateAvoidsImplicitlyUnwrappedStoredProperties() throws {
        let sourceURL = URL(
            fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("NSStatusItem!"))
        XCTAssertFalse(source.contains("MenuBarServicing)!"))
    }

    func testMenuBarResolvedCLIPathDebugLogsAreRedacted() throws {
        let sourceURL = URL(
            fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("updatebar: \\(resolution.path)"))
        XCTAssertTrue(source.contains("SecretRedactor.redact(resolution.path)"))
    }

    func testMenuBarDebugLogRedactsMessagesCentrally() throws {
        let sourceURL = URL(
            fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("SecretRedactor.redact(message)"))
        XCTAssertTrue(source.contains("UpdateBarMenuBar: \\(redactedMessage)\\n"))
        XCTAssertTrue(source.contains("appendLog(redactedMessage)"))
        XCTAssertFalse(source.contains("appendLog(message)"))
    }

    func testMenuBarStatusItemDoesNotShowBrandFallback() throws {
        let sourceURL = URL(
            fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains(#""UB""#))
        XCTAssertTrue(source.contains(#"statusButton.title = "...""#))
        XCTAssertTrue(source.contains(#"badgeValue: "...""#))
        XCTAssertTrue(source.contains(#"latestState.badgeValue ?? "✓""#))
    }

    func testAllCancellationOutcomesRefreshBeforeMutationRowsReturn() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"),
            encoding: .utf8
        )
        let runActionSource = try functionSource(
            named: "private func runAction(",
            endingAt: "private func rebuildMenu()",
            in: source
        )
        XCTAssertTrue(
            runActionSource.contains(
                "self.actionCoordinator.finish(activeAction,outcome:wasCancelled?.cancelled:.finished)self.refreshStatus(refresh:false)"
            )
        )
        let explicitCancellationRefresh =
            "self.actionCoordinator.finish(activeAction,outcome:.cancelled)self.refreshStatus(refresh:false)"
        XCTAssertEqual(
            runActionSource.components(separatedBy: explicitCancellationRefresh).count - 1,
            2
        )
        XCTAssertFalse(
            runActionSource.contains(
                "self.actionCoordinator.finish(activeAction,outcome:.cancelled)self.rebuildMenu()"
            )
        )
        XCTAssertTrue(
            runActionSource.contains(
                "self.actionCoordinator.finish(activeAction,outcome:.failed)self.showError(error)"
            )
        )
    }

    func testRefreshAndActionTransitionsProtectInstalledMenuState() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"),
            encoding: .utf8
        )
        let refreshSource = try functionSource(
            named: "private func refreshStatus(",
            endingAt: "private func runAction(",
            in: source
        )
        let activeActionGuard = try XCTUnwrap(
            refreshSource.range(
                of: "guardactionCoordinator.activeAction==nilelse{rebuildMenu()return}"
            )
        )
        let generationBegin = try XCTUnwrap(
            refreshSource.range(of: "refreshGenerationGate.begin()")
        )
        let loadingMenu = try XCTUnwrap(refreshSource.range(of: "menuBuilder.makeLoadingMenu()"))
        let backgroundRefresh = try XCTUnwrap(
            refreshSource.range(of: "DispatchQueue.global(qos:.userInitiated).async")
        )

        XCTAssertLessThan(activeActionGuard.lowerBound, generationBegin.lowerBound)
        XCTAssertLessThan(activeActionGuard.lowerBound, loadingMenu.lowerBound)
        XCTAssertLessThan(loadingMenu.lowerBound, backgroundRefresh.lowerBound)
        XCTAssertTrue(refreshSource.contains("statusItem?.menu=makeMenu("))

        let runActionSource = try functionSource(
            named: "private func runAction(",
            endingAt: "private func rebuildMenu()",
            in: source
        )
        let invalidate = try XCTUnwrap(
            runActionSource.range(of: "refreshGenerationGate.invalidate()")
        )
        let backgroundAction = try XCTUnwrap(
            runActionSource.range(of: "DispatchQueue.global(qos:.userInitiated).async")
        )

        XCTAssertLessThan(invalidate.lowerBound, backgroundAction.lowerBound)
    }

    func testShowErrorPreservesActiveActionThenInvalidatesOlderRefresh() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"),
            encoding: .utf8
        )
        let errorSource = try functionSource(
            named: "private func showError(",
            endingAt: "private func setTitle(",
            in: source
        )
        let activeActionGuard = try XCTUnwrap(
            errorSource.range(
                of: "guardactionCoordinator.activeAction==nilelse{rebuildMenu()return}"
            )
        )
        let invalidate = try XCTUnwrap(
            errorSource.range(of: "refreshGenerationGate.invalidate()")
        )
        let errorTitle = try XCTUnwrap(
            errorSource.range(of: "setTitle(\"!\",accessibilityLabel:\"UpdateBarerror\")")
        )
        let errorMenu = try XCTUnwrap(errorSource.range(of: "menuBuilder.makeErrorMenu("))

        XCTAssertLessThan(activeActionGuard.lowerBound, invalidate.lowerBound)
        XCTAssertLessThan(invalidate.lowerBound, errorTitle.lowerBound)
        XCTAssertLessThan(invalidate.lowerBound, errorMenu.lowerBound)
    }

    func testDashboardWindowUsesDashboardTitle() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(#"window.title = "Dashboard""#))
        XCTAssertFalse(source.contains(#"window.title = "Overview""#))
    }

    func testMenuBarStatusItemUsesNativeMenuRouting() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("statusButton.target"))
        XCTAssertFalse(source.contains("statusButton.action"))
        XCTAssertFalse(source.contains("statusButton.sendAction"))
        XCTAssertFalse(source.contains("togglePopover"))
        XCTAssertFalse(source.contains("MenuBarPopoverController"))

        let rebuildSource = try functionSource(
            named: "private func rebuildMenu()",
            endingAt: "private func makeMenu(from",
            in: source
        )
        XCTAssertTrue(rebuildSource.contains("letmodel=menuBuilder.makeMenu("))
        XCTAssertTrue(rebuildSource.contains("statusItem.menu=makeMenu(from:model)"))

        let errorSource = try functionSource(
            named: "private func showError(",
            endingAt: "private func setTitle(",
            in: source
        )
        XCTAssertTrue(errorSource.contains("letmodel=menuBuilder.makeErrorMenu("))
        XCTAssertTrue(errorSource.contains("statusItem.menu=makeMenu(from:model)"))
    }

    func testCustomPopoverSourcesAreRemoved() {
        let paths = [
            "Sources/UpdateBarMenuBarApp/MenuBarPopoverView.swift",
            "Sources/UpdateBarMenuBarApp/MenuBarPopoverController.swift",
            "Sources/UpdateBarMenuBar/MenuBarPopoverModel.swift",
            "Tests/UpdateBarMenuBarTests/MenuBarPopoverModelTests.swift",
            "Sources/UpdateBarMenuBarApp/DashboardPopoverView.swift",
            "Sources/UpdateBarMenuBarApp/DashboardPopoverController.swift",
            "Sources/UpdateBarMenuBar/DashboardPopoverModel.swift",
            "Tests/UpdateBarMenuBarTests/DashboardPopoverModelTests.swift",
        ]

        for path in paths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path), path)
        }
    }

    func testDashboardUsesOneTabbedWindowWithEmbeddedItems() throws {
        let dashboardSource = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardPanelController.swift"),
            encoding: .utf8
        )
        let manageItemsSource = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift"),
            encoding: .utf8
        )
        let dashboardCompact = dashboardSource.filter { !$0.isWhitespace }
        let manageItemsCompact = manageItemsSource.filter { !$0.isWhitespace }

        XCTAssertTrue(dashboardSource.contains("enum DashboardTab: Int"))
        XCTAssertTrue(dashboardSource.contains("case overview"))
        XCTAssertTrue(dashboardSource.contains("case items"))
        XCTAssertTrue(
            dashboardCompact.contains("privatelettabViewController=NSTabViewController()"))
        XCTAssertTrue(dashboardCompact.contains("tabViewController.tabStyle=.toolbar"))
        XCTAssertTrue(dashboardSource.contains("private let overviewHostingView:"))
        XCTAssertEqual(dashboardSource.components(separatedBy: "NSHostingView(").count - 1, 1)
        XCTAssertTrue(
            dashboardCompact.contains("overviewViewController.view=overviewHostingView"))
        XCTAssertTrue(
            dashboardCompact.contains("overviewHostingView.rootView=AnyView(view)"))
        XCTAssertTrue(dashboardSource.contains("overviewItem.label = \"Overview\""))
        XCTAssertTrue(dashboardSource.contains("itemsItem.label = \"Items\""))
        XCTAssertTrue(dashboardSource.contains("ManageItemsViewController"))
        XCTAssertTrue(
            dashboardCompact.contains("funcshowWindowAndReload(selectingtab:DashboardTab)"))
        XCTAssertTrue(
            dashboardSource.contains("final class DashboardPanelController: NSWindowController"))
        XCTAssertFalse(dashboardSource.contains("Label(\"Manage Items\""))
        XCTAssertFalse(dashboardSource.contains("onOpenItems"))

        XCTAssertTrue(
            manageItemsCompact.contains(
                "finalclassManageItemsViewController:NSViewController,NSTableViewDataSource,NSTableViewDelegate"
            ))
        XCTAssertTrue(manageItemsSource.contains("func apply(items: [StatusItem]"))
        XCTAssertTrue(manageItemsSource.contains("var onRefresh: () -> Void"))
        XCTAssertFalse(manageItemsSource.contains("service.status("))
        XCTAssertFalse(manageItemsSource.contains("private func present("))
        XCTAssertFalse(manageItemsSource.contains("ManageItemsPanelController"))
        XCTAssertFalse(manageItemsSource.contains("NSPanel("))
        XCTAssertFalse(manageItemsSource.contains("showWindowAndReload"))
    }

    func testNativeMenuRoutesDashboardAndItemsToOneWindow() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"),
            encoding: .utf8
        )
        let compact = source.filter { !$0.isWhitespace }
        let selectorSource = try functionSource(
            named: "private func selector(for action: MenuBarMenuAction)",
            endingAt: "private func disabledItem(",
            in: source
        )

        XCTAssertTrue(compact.contains("@objcprivatefuncshowOverview(){showDashboard(.overview)}"))
        XCTAssertTrue(compact.contains("@objcprivatefuncmanageItems(){showDashboard(.items)}"))
        XCTAssertTrue(
            selectorSource.contains("case.overview:return#selector(showOverview)"))
        XCTAssertTrue(
            selectorSource.contains("case.manageItems:return#selector(manageItems)"))
        XCTAssertFalse(source.contains("DashboardPopover"))
        XCTAssertFalse(source.contains("ManageItemsPanelController"))
        XCTAssertFalse(source.contains("NSMenuDelegate"))
        XCTAssertFalse(source.contains("menu.delegate = self"))
        XCTAssertFalse(source.contains("statusButton.target"))
        XCTAssertFalse(source.contains("statusButton.action"))
        XCTAssertFalse(source.contains("statusButton.sendAction"))
        XCTAssertTrue(compact.contains("dashboardPanelController?.reloadIfShown()"))
    }

    func testDashboardSharesOneRefreshAcrossTabsAndRejectsStaleResults() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardPanelController.swift"),
            encoding: .utf8
        )
        let compact = source.filter { !$0.isWhitespace }
        let reloadSource = try functionSource(
            named: "func reload()",
            endingAt: "private func apply(",
            in: source
        )

        XCTAssertEqual(reloadSource.components(separatedBy: "service.status(").count - 1, 1)
        XCTAssertTrue(compact.contains("privatevarreloadGeneration=0"))
        XCTAssertTrue(reloadSource.contains("reloadGeneration&+=1"))
        XCTAssertTrue(reloadSource.contains("letgeneration=reloadGeneration"))
        XCTAssertTrue(reloadSource.contains("guardgeneration==self.reloadGenerationelse{return}"))
        XCTAssertTrue(reloadSource.contains("manageItemsViewController.apply(items:snapshot.items"))
        XCTAssertTrue(source.contains("func reloadIfShown()"))
        XCTAssertTrue(source.contains("func showErrorIfShown(_ error: Error)"))
        XCTAssertTrue(source.contains("NSWindowDelegate"))
        XCTAssertTrue(compact.contains("window.delegate=self"))

        let closeSource = try functionSource(
            named: "func windowWillClose(",
            endingAt: "private func apply(",
            in: source
        )
        let errorSource = try functionSource(
            named: "private func presentDashboardError(",
            endingAt: "    }\n#endif",
            in: source
        )
        XCTAssertTrue(closeSource.contains("reloadGeneration&+=1"))
        XCTAssertTrue(errorSource.contains("window.isVisible"))
    }

    func testItemToggleStaysDisabledUntilSharedSnapshotArrives() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift"),
            encoding: .utf8
        )
        let toggleSource = try functionSource(
            named: "@objc private func toggleItem(",
            endingAt: "func setLoading()",
            in: source
        )

        let waiting = try XCTUnwrap(toggleSource.range(of: "self.setRunning(true"))
        let changed = try XCTUnwrap(toggleSource.range(of: "self.onChanged()"))
        XCTAssertLessThan(waiting.lowerBound, changed.lowerBound)
        XCTAssertFalse(toggleSource.contains("self.setRunning(false"))
    }

    func testMenuRefreshPropagatesResultToVisibleDashboard() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"),
            encoding: .utf8
        )
        let refreshSource = try functionSource(
            named: "private func refreshStatus(refresh: Bool)",
            endingAt: "private func runAction(",
            in: source
        )
        let errorSource = try functionSource(
            named: "private func showError(",
            endingAt: "private func setTitle(",
            in: source
        )

        XCTAssertTrue(refreshSource.contains("dashboardPanelController?.reloadIfShown()"))
        XCTAssertTrue(errorSource.contains("dashboardPanelController?.showErrorIfShown(error)"))
    }

    func testDashboardWindowControlsApplicationSwitcherVisibility() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"),
            encoding: .utf8
        )
        let showDashboardSource = try functionSource(
            named: "private func showDashboard(_ tab: DashboardTab)",
            endingAt: "@objc private func applicationWindowWillClose(",
            in: source
        )
        let windowCloseSource = try functionSource(
            named: "@objc private func applicationWindowWillClose(",
            endingAt: "private func restoreAccessoryActivationPolicyIfNeeded()",
            in: source
        )
        let restoreSource = try functionSource(
            named: "private func restoreAccessoryActivationPolicyIfNeeded()",
            endingAt: "@objc private func openTUIInTerminal(",
            in: source
        )

        let regular = try XCTUnwrap(
            showDashboardSource.range(of: "NSApp.setActivationPolicy(.regular)"))
        let show = try XCTUnwrap(
            showDashboardSource.range(of: "showWindowAndReload(selecting:tab)"))
        XCTAssertLessThan(regular.lowerBound, show.lowerBound)
        XCTAssertTrue(source.contains("name: NSWindow.willCloseNotification"))
        XCTAssertTrue(windowCloseSource.contains("restoreAccessoryActivationPolicyIfNeeded()"))

        XCTAssertTrue(restoreSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(restoreSource.contains("$0.isVisible"))
        XCTAssertTrue(restoreSource.contains("$0.styleMask.contains(.titled)"))
        XCTAssertTrue(restoreSource.contains("guard!hasVisibleTitledWindowelse{return}"))
        XCTAssertTrue(restoreSource.contains("NSApp.setActivationPolicy(.accessory)"))
    }

    private func functionSource(
        named startMarker: String,
        endingAt endMarker: String,
        in source: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker))
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start.upperBound..<source.endIndex)
        )
        return String(source[start.lowerBound..<end.lowerBound]).filter { !$0.isWhitespace }
    }
}
