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

        let compactViewSource = viewSource.filter { !$0.isWhitespace }
        XCTAssertTrue(compactViewSource.contains(".buttonStyle(.plain).commandRowStyle()"))
        XCTAssertEqual(
            compactViewSource.components(
                separatedBy: ".menuStyle(.borderlessButton).commandRowStyle()"
            ).count - 1,
            2
        )

        guard
            let modifierStart = viewSource.range(
                of: "private struct CommandRowModifier: ViewModifier"),
            let modifierEnd = viewSource.range(
                of: "extension View",
                range: modifierStart.upperBound..<viewSource.endIndex
            )
        else {
            XCTFail("Popover commands must share a control-level command-row modifier")
            return
        }

        let modifierSource = viewSource[modifierStart.lowerBound..<modifierEnd.lowerBound]
            .filter { !$0.isWhitespace }
        XCTAssertTrue(modifierSource.contains("@FocusStateprivatevarisFocused:Bool"))
        XCTAssertTrue(
            modifierSource.contains(
                ".frame(maxWidth:.infinity,minHeight:26,alignment:.leading)"
            )
        )
        XCTAssertTrue(modifierSource.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(modifierSource.contains(".focused($isFocused)"))
        XCTAssertTrue(modifierSource.contains("isFocused?Color.accentColor"))
        XCTAssertTrue(modifierSource.contains(".onHover{isHovered=$0}"))
    }
}
