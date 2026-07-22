#if os(macOS)
    import AppKit
    import UpdateBarMenuBar
    import XCTest

    final class MenuBarSystemImageRendererTests: XCTestCase {
        func testValidSystemSymbolSetsTemplateImageAndAccessibilityDescription() throws {
            let menuItem = NSMenuItem(title: "Refresh", action: nil, keyEquivalent: "")

            MenuBarSystemImageRenderer.apply(
                systemSymbolName: "arrow.clockwise",
                applicationIcon: nil,
                accessibilityDescription: "Refresh updates",
                to: menuItem
            )

            let image = try XCTUnwrap(menuItem.image)
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.accessibilityDescription, "Refresh updates")
        }

        func testApplicationIconWinsAndIsSizedAfterSystemSymbol() throws {
            let menuItem = NSMenuItem(title: "Open TUI", action: nil, keyEquivalent: "")
            let applicationIcon = NSImage(size: NSSize(width: 48, height: 32))

            MenuBarSystemImageRenderer.apply(
                systemSymbolName: "terminal",
                applicationIcon: applicationIcon,
                accessibilityDescription: "Open TUI",
                to: menuItem
            )

            XCTAssertTrue(menuItem.image === applicationIcon)
            XCTAssertEqual(applicationIcon.size, NSSize(width: 16, height: 16))
        }

        func testMissingSystemSymbolLeavesExistingImageUnchanged() throws {
            let sentinelForNil = NSImage(size: NSSize(width: 12, height: 12))
            let nilSymbolItem = NSMenuItem(title: "No symbol", action: nil, keyEquivalent: "")
            nilSymbolItem.image = sentinelForNil

            MenuBarSystemImageRenderer.apply(
                systemSymbolName: nil,
                applicationIcon: nil,
                accessibilityDescription: "No symbol",
                to: nilSymbolItem
            )

            XCTAssertTrue(nilSymbolItem.image === sentinelForNil)

            let sentinelForUnavailable = NSImage(size: NSSize(width: 12, height: 12))
            let unavailableSymbolItem = NSMenuItem(
                title: "Unavailable symbol",
                action: nil,
                keyEquivalent: ""
            )
            unavailableSymbolItem.image = sentinelForUnavailable

            MenuBarSystemImageRenderer.apply(
                systemSymbolName: "com.updatebar.definitely-unavailable-system-symbol",
                applicationIcon: nil,
                accessibilityDescription: "Unavailable symbol",
                to: unavailableSymbolItem
            )

            XCTAssertTrue(unavailableSymbolItem.image === sentinelForUnavailable)
        }
    }
#endif
