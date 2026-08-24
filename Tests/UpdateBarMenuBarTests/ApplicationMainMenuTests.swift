#if os(macOS)
    import AppKit
    @testable import UpdateBarMenuBarApp
    import XCTest

    @MainActor
    final class ApplicationMainMenuTests: XCTestCase {
        func testMainMenuMapsCommandWToCloseWindowResponderAction() throws {
            let menu = UpdateBarMenuBarApp.makeMainMenu()
            let fileMenu = try XCTUnwrap(menu.item(withTitle: "File")?.submenu)
            let closeWindow = try XCTUnwrap(fileMenu.item(withTitle: "Close Window"))

            XCTAssertEqual(closeWindow.keyEquivalent, "w")
            XCTAssertEqual(
                closeWindow.keyEquivalentModifierMask,
                NSEvent.ModifierFlags.command
            )
            XCTAssertEqual(closeWindow.action, #selector(NSWindow.performClose(_:)))
            XCTAssertNil(closeWindow.target)
        }

        func testApplicationBootstrapInstallsTheMainMenu() throws {
            let source = try String(
                contentsOf: URL(
                    fileURLWithPath:
                        "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift"
                ),
                encoding: .utf8
            )

            XCTAssertTrue(source.contains("app.mainMenu = makeMainMenu()"))
        }
    }
#endif
