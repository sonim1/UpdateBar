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
