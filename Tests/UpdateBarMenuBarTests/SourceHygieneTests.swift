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

    func testDashboardSectionsUseCompactCopyWithAccessibleHelp() throws {
        let overviewPath = "Sources/UpdateBarMenuBarApp/DashboardOverviewView.swift"
        XCTAssertTrue(FileManager.default.fileExists(atPath: overviewPath))
        let overview = try String(
            contentsOf: URL(fileURLWithPath: overviewPath),
            encoding: .utf8
        )
        let panel = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardPanelController.swift"),
            encoding: .utf8
        )
        let items = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift"),
            encoding: .utf8
        )
        let scan = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/ScanViewController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(overview.contains(#"Text("Overview")"#))
        XCTAssertTrue(overview.contains("DashboardPresentationModel"))
        XCTAssertTrue(overview.contains(".help(metric.help)"))
        XCTAssertTrue(overview.contains(".accessibilityLabel(metric.accessibilityLabel)"))
        XCTAssertTrue(overview.contains(".accessibilityValue(metric.accessibilityValue)"))
        XCTAssertFalse(overview.contains(#"Text("UpdateBar")"#))
        XCTAssertFalse(overview.contains("statusText"))
        XCTAssertFalse(overview.contains("Text(title)"))
        XCTAssertFalse(overview.contains("Updates · last 4 weeks"))
        XCTAssertFalse(panel.contains("private struct DashboardView"))
        XCTAssertFalse(panel.contains("import Accessibility"))
        XCTAssertFalse(panel.contains("import Charts"))
        XCTAssertTrue(panel.contains("DashboardOverviewView(summary: summary)"))

        XCTAssertTrue(items.contains(#"labelWithString: "Items""#))
        XCTAssertTrue(items.contains(#"systemSymbolName: "arrow.clockwise""#))
        XCTAssertTrue(items.contains("DashboardPresentationModel.itemsRefreshHelp"))
        XCTAssertTrue(items.contains("refreshButton.toolTip"))
        XCTAssertTrue(items.contains("refreshButton.setAccessibilityLabel"))
        XCTAssertTrue(items.contains("NSProgressIndicator"))
        XCTAssertTrue(items.contains("mutationGate.isPending(id:"))
        XCTAssertTrue(items.contains(#"systemSymbolName: "exclamationmark.triangle.fill""#))
        XCTAssertFalse(items.contains(#"NSButton(title: "Refresh""#))
        XCTAssertFalse(items.contains("private let statusLabel"))
        XCTAssertFalse(items.contains("statusLabel.stringValue"))
        XCTAssertFalse(items.contains(#"labelWithString: "Ready""#))

        XCTAssertTrue(scan.contains(#"labelWithString: "Scan & Add""#))
        XCTAssertTrue(scan.contains(#"NSButton(title: "Scan""#))
        XCTAssertTrue(scan.contains("DashboardPresentationModel.scanTrackingHelp"))
        XCTAssertTrue(scan.contains("presentationModel.scanCounts("))
        XCTAssertTrue(scan.contains("final class ScanCountBadgeView: NSTextField"))
        XCTAssertTrue(scan.contains("badge.apply(count)"))
        XCTAssertTrue(scan.contains("setAccessibilityElement(true)"))
        XCTAssertFalse(scan.contains("private let valueLabel"))
        XCTAssertFalse(scan.contains("addSubview(valueLabel)"))
        XCTAssertTrue(scan.contains("NSProgressIndicator"))
        XCTAssertTrue(scan.contains("presentationModel.scanControl(state: scanControlState)"))
        XCTAssertTrue(scan.contains("scanControlState = .scanning"))
        XCTAssertTrue(scan.contains("scanControlState = .failed"))
        XCTAssertTrue(scan.contains("presentationModel.scanRowActionLabel("))
        XCTAssertTrue(scan.contains("presentationModel.scanMutationFailureAnnouncement("))
        XCTAssertTrue(scan.contains("NSAccessibility.post("))
        XCTAssertTrue(scan.contains("notification: .announcementRequested"))
        XCTAssertTrue(scan.contains(".announcement: announcement"))
        XCTAssertTrue(scan.contains(".priority: NSAccessibilityPriorityLevel.high.rawValue"))
        XCTAssertFalse(scan.contains("statusLabel"))
        XCTAssertFalse(scan.contains(#"labelWithString: "Discovered""#))
        XCTAssertFalse(scan.contains(#"labelWithString: "Enabled""#))
        XCTAssertFalse(scan.contains(#"labelWithString: "Disabled""#))
        XCTAssertFalse(scan.contains(#""Scanning...""#))
        XCTAssertFalse(scan.contains("Scan complete"))
        XCTAssertFalse(scan.contains(#""Updated.""#))
        XCTAssertFalse(scan.contains("Update failed"))
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

    func testDashboardUsesOneSidebarWindowWithThreeEmbeddedSections() throws {
        let dashboardSource = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardPanelController.swift"),
            encoding: .utf8
        )
        let sidebarSource = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift"),
            encoding: .utf8
        )
        let manageItemsSource = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/ManageItemsPanelController.swift"),
            encoding: .utf8
        )
        let dashboardCompact = dashboardSource.filter { !$0.isWhitespace }
        let sidebarCompact = sidebarSource.filter { !$0.isWhitespace }
        let manageItemsCompact = manageItemsSource.filter { !$0.isWhitespace }

        XCTAssertTrue(
            dashboardCompact.contains("privateletsplitViewController=NSSplitViewController()"))
        XCTAssertTrue(
            dashboardSource.contains("DashboardSidebarViewController"))
        XCTAssertTrue(sidebarSource.contains("NSTableViewDataSource"))
        XCTAssertTrue(sidebarSource.contains("NSTableViewDelegate"))
        XCTAssertTrue(sidebarCompact.contains("tableView.headerView=nil"))
        XCTAssertTrue(sidebarCompact.contains("tableView.style=.sourceList"))
        XCTAssertTrue(sidebarCompact.contains("NSImage(systemSymbolName:"))
        XCTAssertTrue(sidebarSource.contains("setAccessibilityLabel"))
        XCTAssertTrue(sidebarSource.contains("setAccessibilitySelected"))
        XCTAssertTrue(
            sidebarSource.contains("widthAnchor.constraint(greaterThanOrEqualToConstant: 150)"))
        XCTAssertTrue(
            sidebarSource.contains("widthAnchor.constraint(lessThanOrEqualToConstant: 190)"))
        XCTAssertTrue(dashboardSource.contains("private let overviewHostingView:"))
        XCTAssertEqual(dashboardSource.components(separatedBy: "NSHostingView(").count - 1, 1)
        XCTAssertTrue(
            dashboardCompact.contains("overviewViewController.view=overviewHostingView"))
        XCTAssertTrue(
            dashboardCompact.contains("overviewHostingView.rootView=AnyView(view)"))
        XCTAssertTrue(dashboardSource.contains("ManageItemsViewController"))
        XCTAssertTrue(dashboardSource.contains("ScanViewController"))
        XCTAssertTrue(dashboardSource.contains("contentContainerViewController"))
        XCTAssertTrue(
            dashboardCompact.contains(
                "funcshowWindowAndReload(selectingsection:DashboardSection)"))
        XCTAssertTrue(
            dashboardSource.contains("final class DashboardPanelController: NSWindowController"))
        XCTAssertFalse(dashboardSource.contains("NSTabViewController"))
        XCTAssertFalse(dashboardSource.contains("segmentedControlOnTop"))
        XCTAssertFalse(dashboardSource.contains("DashboardTab"))
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

    func testEmbeddedScanReplacesStandalonePanelAndBindsHelpAndAccessibility() throws {
        let scanPath = "Sources/UpdateBarMenuBarApp/ScanViewController.swift"
        let oldPath = "Sources/UpdateBarMenuBarApp/ScanPanelController.swift"
        XCTAssertTrue(FileManager.default.fileExists(atPath: scanPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPath))

        let source = try String(
            contentsOf: URL(fileURLWithPath: scanPath),
            encoding: .utf8
        )
        let compact = source.filter { !$0.isWhitespace }

        XCTAssertTrue(
            compact.contains(
                "finalclassScanViewController:NSViewController,NSTableViewDataSource,NSTableViewDelegate"
            ))
        XCTAssertFalse(source.contains("NSPanel("))
        XCTAssertFalse(source.contains("showScanWindow"))
        XCTAssertFalse(source.contains("Add Selected"))
        XCTAssertFalse(source.contains("addSelected"))
        XCTAssertTrue(source.contains("NSButton(title: \"Scan\""))
        XCTAssertTrue(source.contains("var onError: (Error) -> Void"))
        XCTAssertTrue(source.contains("func applyRegisteredItems(_ items: [StatusItem])"))
        XCTAssertTrue(source.contains("func invalidateScanSession()"))
        XCTAssertTrue(source.contains("toolTip ="))
        XCTAssertTrue(source.contains("setAccessibilityLabel"))
        XCTAssertTrue(compact.contains("state=row.stateLabel.capitalized"))
        let performSource = try functionSource(
            named: "private func perform(_ mutation: ScanRowMutation",
            endingAt: "private func finishScan(",
            in: source
        )
        XCTAssertTrue(
            performSource.contains("guardletintent=mutation.serviceIntentelse{return}"))
        XCTAssertTrue(performSource.contains("switchintent"))
        XCTAssertFalse(performSource.contains("switchmutation.previous"))
        XCTAssertTrue(
            source.contains(
                "DashboardPresentationModel.scanTrackingHelp"
            ))
    }

    func testNativeMenuRoutesAllDashboardSectionsToOneWindow() throws {
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
        let dashboardActionSource = try functionSource(
            named: "private func showDashboard(for action: MenuBarMenuAction)",
            endingAt: "private func showDashboard(_ section: DashboardSection)",
            in: source
        )

        XCTAssertTrue(
            compact.contains("@objcprivatefuncshowOverview(){showDashboard(for:.overview)}"))
        XCTAssertTrue(
            compact.contains("@objcprivatefuncmanageItems(){showDashboard(for:.manageItems)}"))
        XCTAssertTrue(
            compact.contains("@objcprivatefuncscanAndAdd(){showDashboard(for:.scanAndAdd)}"))
        XCTAssertTrue(
            compact.contains("privateletdashboardNavigationModel=DashboardNavigationModel()"))
        XCTAssertTrue(
            dashboardActionSource.contains(
                "dashboardNavigationModel.section(for:action)"))
        XCTAssertTrue(dashboardActionSource.contains("showDashboard(section)"))
        XCTAssertTrue(
            selectorSource.contains("case.overview:return#selector(showOverview)"))
        XCTAssertTrue(
            selectorSource.contains("case.manageItems:return#selector(manageItems)"))
        XCTAssertTrue(
            selectorSource.contains("case.scanAndAdd:return#selector(scanAndAdd)"))
        XCTAssertFalse(source.contains("DashboardPopover"))
        XCTAssertFalse(source.contains("ManageItemsPanelController"))
        XCTAssertFalse(source.contains("ScanPanelController"))
        XCTAssertFalse(source.contains("scanPanelController"))
        XCTAssertEqual(source.components(separatedBy: "DashboardPanelController(").count - 1, 1)
        XCTAssertFalse(source.contains("NSMenuDelegate"))
        XCTAssertFalse(source.contains("menu.delegate = self"))
        XCTAssertFalse(source.contains("statusButton.target"))
        XCTAssertFalse(source.contains("statusButton.action"))
        XCTAssertFalse(source.contains("statusButton.sendAction"))
        XCTAssertTrue(compact.contains("dashboardPanelController?.reloadIfShown()"))
    }

    func testDashboardSharesOneRefreshAcrossSectionsAndRejectsStaleResults() throws {
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
        XCTAssertEqual(reloadSource.components(separatedBy: "service.history(").count - 1, 1)
        XCTAssertTrue(compact.contains("privatevarreloadGeneration=0"))
        XCTAssertTrue(reloadSource.contains("reloadGeneration&+=1"))
        XCTAssertTrue(reloadSource.contains("letgeneration=reloadGeneration"))
        XCTAssertTrue(reloadSource.contains("guardgeneration==self.reloadGenerationelse{return}"))
        XCTAssertTrue(reloadSource.contains("manageItemsViewController.apply(items:snapshot.items"))
        XCTAssertTrue(
            reloadSource.contains("scanViewController.applyRegisteredItems(snapshot.items)"))
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
        XCTAssertTrue(closeSource.contains("scanViewController.invalidateScanSession()"))
        XCTAssertTrue(errorSource.contains("window.isVisible"))

        let selectSource = try functionSource(
            named: "private func select(_ section: DashboardSection)",
            endingAt: "private func controller(for section: DashboardSection)",
            in: source
        )
        XCTAssertTrue(selectSource.contains("navigationModel.select(section)"))
        XCTAssertTrue(
            selectSource.contains(
                "sidebarViewController.select(navigationModel.selectedSection)"))
        XCTAssertTrue(
            selectSource.contains(
                "showContent(controller(for:navigationModel.selectedSection))"))
    }

    func testSuccessfulScanCommitInvalidatesReloadBeforeSharedRefresh() throws {
        let dashboardSource = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardPanelController.swift"),
            encoding: .utf8
        )
        let scanSource = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/ScanViewController.swift"),
            encoding: .utf8
        )
        let callbackSource = try functionSource(
            named: "scanViewController.onChanged = {",
            endingAt: "sidebarViewController.onSelectionChanged = {",
            in: dashboardSource
        )
        let finishSource = try functionSource(
            named: "private func finishMutation(id: String)",
            endingAt: "private func finishMutationFailure(",
            in: scanSource
        )

        let invalidate = try XCTUnwrap(callbackSource.range(of: "self.reloadGeneration&+=1"))
        let refresh = try XCTUnwrap(callbackSource.range(of: "onItemsChanged()"))
        XCTAssertLessThan(invalidate.lowerBound, refresh.lowerBound)
        XCTAssertTrue(scanSource.contains("var onChanged: () -> Void"))
        XCTAssertTrue(finishSource.contains("onChanged()"))
    }

    func testDashboardQueuesRedactedErrorsAndAdvancesSheetsSerially() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardPanelController.swift"),
            encoding: .utf8
        )
        let compact = source.filter { !$0.isWhitespace }
        let enqueueSource = try functionSource(
            named: "private func presentDashboardError(_ error: Error)",
            endingAt: "private func presentNextDashboardErrorIfPossible()",
            in: source
        )
        let presentationSource = try functionSource(
            named: "private func presentNextDashboardErrorIfPossible()",
            endingAt: "    }\n#endif",
            in: source
        )
        let closeSource = try functionSource(
            named: "func windowWillClose(",
            endingAt: "private func select(",
            in: source
        )

        XCTAssertTrue(compact.contains("privatevardashboardErrorQueue=DashboardErrorQueue()"))
        XCTAssertTrue(
            enqueueSource.contains(
                "dashboardErrorQueue.enqueue(SecretRedactor.redact(String(describing:error)))"
            ))
        XCTAssertFalse(enqueueSource.contains("attachedSheet"))
        XCTAssertTrue(presentationSource.contains("window.attachedSheet==nil"))
        XCTAssertTrue(presentationSource.contains("dashboardErrorQueue.beginNextPresentation()"))
        XCTAssertTrue(presentationSource.contains("alert.beginSheetModal(for:window)"))
        XCTAssertTrue(
            presentationSource.contains(
                "dashboardErrorQueue.finishPresentation(token:presentation.token)"
            ))
        XCTAssertTrue(presentationSource.contains("presentNextDashboardErrorIfPossible()"))
        XCTAssertTrue(closeSource.contains("dashboardErrorQueue.clear()"))
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

        let waiting = try XCTUnwrap(toggleSource.range(of: "mutationGate.begin("))
        let changed = try XCTUnwrap(toggleSource.range(of: "self.onChanged()"))
        XCTAssertLessThan(waiting.lowerBound, changed.lowerBound)
        XCTAssertFalse(toggleSource.contains("mutationGate.cancel()"))
        XCTAssertTrue(source.contains("button.isEnabled = !isLoading && !mutationGate.isPending"))
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
            named: "private func showDashboard(_ section: DashboardSection)",
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
            showDashboardSource.range(of: "showWindowAndReload(selecting:section)"))
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
