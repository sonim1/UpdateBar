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

    func testMenuBarPopoverUsesCompactNativeMenuLayout() throws {
        let viewSource = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/MenuBarPopoverView.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: URL(
                fileURLWithPath: "Sources/UpdateBarMenuBarApp/MenuBarPopoverController.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(viewSource.contains("LazyVGrid"))
        XCTAssertFalse(viewSource.contains("commandGrid"))
        XCTAssertFalse(viewSource.contains("private func metric("))
        XCTAssertFalse(viewSource.contains(".background(.quaternary"))
        XCTAssertTrue(viewSource.contains("Picker(\"Section\", selection: $selectedTab)"))
        XCTAssertTrue(viewSource.contains(".pickerStyle(.segmented)"))
        XCTAssertTrue(viewSource.contains("CGSize(width: 340, height: 520)"))
        XCTAssertTrue(viewSource.contains("MenuBarPopoverLayout.size.width"))
        XCTAssertTrue(controllerSource.contains("MenuBarPopoverLayout.size"))
        XCTAssertFalse(controllerSource.contains("NSSize(width:"))
    }
}
