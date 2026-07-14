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
        ]

        for path in paths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path), path)
        }
    }

    func testDashboardPopoverViewUsesCompactReadOnlySystemControls() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardPopoverView.swift"),
            encoding: .utf8
        )
        let compact = source.filter { !$0.isWhitespace }

        XCTAssertTrue(compact.contains("CGSize(width:340,height:420)"))
        XCTAssertTrue(source.contains("case overview = \"Overview\""))
        XCTAssertTrue(source.contains("case updates = \"Updates\""))
        XCTAssertTrue(source.contains("case approvals = \"Approvals\""))
        XCTAssertTrue(compact.contains("Picker(\"Section\",selection:$selection)"))
        XCTAssertTrue(compact.contains(".pickerStyle(.segmented)"))
        XCTAssertTrue(source.contains("ScrollView"))
        XCTAssertTrue(source.contains("Image(systemName: \"arrow.up.right.square\")"))
        XCTAssertTrue(compact.contains(".buttonStyle(.borderless)"))
        XCTAssertTrue(source.contains(".help(\"Open Full Dashboard\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Open Full Dashboard\")"))
        XCTAssertEqual(source.components(separatedBy: "Button(").count - 1, 1)

        for forbidden in [
            "onRefresh", "onUpdate", "onApprove", "onSettings", "onQuit",
            "CommandGrid", "Text(\"Refresh\")", "Text(\"Settings\")", "Text(\"Quit\")",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    func testDashboardPopoverControllerUsesOneTransientSystemMaterialPopover() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/DashboardPopoverController.swift"),
            encoding: .utf8
        )
        let compact = source.filter { !$0.isWhitespace }

        XCTAssertTrue(compact.contains("privateletpopover=NSPopover()"))
        XCTAssertTrue(source.contains("private let hostingView:"))
        XCTAssertTrue(compact.contains("popover.behavior=.transient"))
        XCTAssertTrue(compact.contains("effectView.material=.popover"))
        XCTAssertTrue(compact.contains("effectView.blendingMode=.behindWindow"))
        XCTAssertTrue(compact.contains("effectView.state=.followsWindowActiveState"))
        XCTAssertTrue(source.contains("func show("))
        XCTAssertTrue(source.contains("func update("))
        XCTAssertTrue(source.contains("func close()"))
        XCTAssertTrue(source.contains("var isShown:"))
        XCTAssertEqual(source.components(separatedBy: "NSHostingView(").count - 1, 1)
    }

    func testDashboardMenuRoutesToPopoverWithoutReplacingNativeMenu() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"),
            encoding: .utf8
        )
        let compact = source.filter { !$0.isWhitespace }
        let launchSource = try functionSource(
            named: "func applicationDidFinishLaunching(",
            endingAt: "func applicationWillTerminate(",
            in: source
        )
        let dashboardSource = try functionSource(
            named: "@objc private func showDashboardPopover()",
            endingAt: "@objc private func showOverview()",
            in: source
        )
        let selectorSource = try functionSource(
            named: "private func selector(for action: MenuBarMenuAction)",
            endingAt: "private func disabledItem(",
            in: source
        )

        XCTAssertTrue(
            compact.contains(
                "privateletdashboardPopoverModelBuilder=DashboardPopoverModelBuilder()"))
        XCTAssertTrue(
            compact.contains("privateletdashboardPopoverController=DashboardPopoverController()"))
        XCTAssertTrue(compact.contains("privatevarlastDashboardError:String?"))
        XCTAssertTrue(launchSource.contains("rebuildMenu()"))
        XCTAssertFalse(launchSource.contains("dashboardPopoverController.show("))
        XCTAssertTrue(
            selectorSource.contains("case.overview:return#selector(showDashboardPopover)"))
        XCTAssertFalse(selectorSource.contains("case.overview:return#selector(showOverview)"))
        XCTAssertTrue(dashboardSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(dashboardSource.contains("[weakself]"))
        XCTAssertTrue(dashboardSource.contains("statusItem?.button"))
        XCTAssertTrue(dashboardSource.contains("self.showOverview()"))
        XCTAssertTrue(dashboardSource.contains("dashboardPopoverController.show("))
        XCTAssertEqual(
            source.components(separatedBy: "dashboardPopoverController.show(").count - 1, 1)
        XCTAssertFalse(source.contains("statusButton.target"))
        XCTAssertFalse(source.contains("statusButton.action"))
        XCTAssertFalse(source.contains("statusButton.sendAction"))
    }

    func testDashboardPopoverTracksRefreshMenuAndErrorTransitions() throws {
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
        let rebuildSource = try functionSource(
            named: "private func rebuildMenu()",
            endingAt: "private func makeMenu(from",
            in: source
        )
        let errorSource = try functionSource(
            named: "private func showError(",
            endingAt: "private func setTitle(",
            in: source
        )

        let clearedError = try XCTUnwrap(refreshSource.range(of: "self.lastDashboardError=nil"))
        let refreshedMenu = try XCTUnwrap(refreshSource.range(of: "self.rebuildMenu()"))
        XCTAssertLessThan(clearedError.lowerBound, refreshedMenu.lowerBound)

        let nativeMenu = try XCTUnwrap(
            rebuildSource.range(of: "statusItem.menu=makeMenu(from:model)"))
        let popoverUpdate = try XCTUnwrap(
            rebuildSource.range(of: "updateDashboardPopoverIfShown()")
        )
        XCTAssertLessThan(nativeMenu.lowerBound, popoverUpdate.lowerBound)

        let redactedError = try XCTUnwrap(
            errorSource.range(
                of: "leterrorDescription=SecretRedactor.redact(String(describing:error))"
            )
        )
        let storedError = try XCTUnwrap(
            errorSource.range(of: "lastDashboardError=errorDescription")
        )
        let activeActionGuard = try XCTUnwrap(
            errorSource.range(
                of: "guardactionCoordinator.activeAction==nilelse{rebuildMenu()return}"
            )
        )
        let invalidate = try XCTUnwrap(errorSource.range(of: "refreshGenerationGate.invalidate()"))
        let errorMenu = try XCTUnwrap(errorSource.range(of: "statusItem.menu=makeMenu(from:model)"))
        let errorPopoverUpdate = try XCTUnwrap(
            errorSource.range(of: "updateDashboardPopoverIfShown()")
        )

        XCTAssertLessThan(redactedError.lowerBound, storedError.lowerBound)
        XCTAssertLessThan(storedError.lowerBound, activeActionGuard.lowerBound)
        XCTAssertLessThan(activeActionGuard.lowerBound, invalidate.lowerBound)
        XCTAssertLessThan(errorMenu.lowerBound, errorPopoverUpdate.lowerBound)
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
