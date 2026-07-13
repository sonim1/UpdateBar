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

    func testSuccessfulActionCompletionRebuildsBeforeRefresh() throws {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"),
            encoding: .utf8
        )
        guard
            let runActionStart = source.range(of: "private func runAction("),
            let runActionEnd = source.range(
                of: "private func rebuildMenu()",
                range: runActionStart.upperBound..<source.endIndex
            )
        else {
            XCTFail("Menu bar action lifecycle methods are missing")
            return
        }

        let runActionSource = source[runActionStart.lowerBound..<runActionEnd.lowerBound]
            .filter { !$0.isWhitespace }
        XCTAssertTrue(
            runActionSource.contains(
                "self.actionCoordinator.finish(activeAction,outcome:wasCancelled?.cancelled:.finished)self.rebuildMenu()if!wasCancelled{self.refreshStatus(refresh:false)}"
            )
        )
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
