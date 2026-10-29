#if os(macOS)
    import AppKit
    import UpdateBarMenuBar
    @testable import UpdateBarMenuBarApp
    import XCTest

    @MainActor
    final class NativeMenuUpdaterTests: XCTestCase {
        private var selectedPayload: String?

        @objc private func selectItem(_ sender: NSMenuItem) {
            selectedPayload = sender.representedObject as? String
        }

        func testRefreshUpdatesTheSameRowWhileNativeMenuIsTracking() {
            _ = NSApplication.shared
            let driver = TrackingRefreshDriver()
            let timer = Timer(
                timeInterval: 0.05, target: driver,
                selector: #selector(TrackingRefreshDriver.refresh), userInfo: nil, repeats: false
            )
            RunLoop.main.add(timer, forMode: .eventTracking)
            defer { timer.invalidate() }

            driver.menu.popUp(positioning: nil, at: NSPoint(x: 180, y: 400), in: nil)

            XCTAssertTrue(driver.updatedWhileOpen)
            XCTAssertTrue(driver.menu.items.first === driver.row)
            XCTAssertEqual(driver.row.title, "alpha — updating…")
        }

        func testRefreshReusesRowsAndUpdatesTheirActionsAndAppearance() throws {
            _ = NSApplication.shared
            let menu = NSMenu()
            let row = item("alpha — queued", id: "alpha")
            menu.addItem(row)
            let replacement = item("alpha — updating…", id: "alpha")
            replacement.toolTip = "Running"
            replacement.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            replacement.action = #selector(selectItem(_:))
            replacement.target = self
            replacement.representedObject = "current payload"
            replacement.isEnabled = false
            let source = NSMenu()
            source.addItem(replacement)

            NativeMenuUpdater.apply(source, to: menu)

            XCTAssertTrue(menu.items.first === row)
            XCTAssertEqual(row.title, replacement.title)
            XCTAssertEqual(row.toolTip, "Running")
            XCTAssertTrue(row.image === replacement.image)
            XCTAssertEqual(row.action, replacement.action)
            XCTAssertTrue(row.target === self)
            XCTAssertEqual(row.representedObject as? String, "current payload")
            XCTAssertFalse(row.isEnabled)
            XCTAssertFalse(menu.autoenablesItems)

            row.isEnabled = true
            menu.performActionForItem(at: 0)
            XCTAssertEqual(selectedPayload, "current payload")
        }

        func testRefreshAddsRemovesAndReordersRowsWithoutReplacingSurvivors() {
            let menu = NSMenu()
            let alpha = item("alpha", id: "alpha")
            let bravo = item("bravo", id: "bravo")
            menu.addItem(alpha)
            menu.addItem(item("removed", id: "removed"))
            menu.addItem(bravo)
            let source = NSMenu()
            for id in ["bravo", "added", "alpha"] { source.addItem(item(id, id: id)) }

            NativeMenuUpdater.apply(source, to: menu)

            XCTAssertEqual(menu.items.map(\.title), ["bravo", "added", "alpha"])
            XCTAssertTrue(menu.items[0] === bravo)
            XCTAssertTrue(menu.items[2] === alpha)
        }

        func testRefreshPreservesSubmenuAndHistoryViewIdentity() throws {
            let menu = NSMenu()
            let parent = item("More", id: "more")
            let child = NSMenu()
            let settings = item("Settings", id: "settings")
            child.addItem(settings)
            parent.submenu = child
            menu.addItem(parent)
            let historyRow = item("", id: "history")
            let historyView = MenuBarUpdateHistoryView(history: .empty)
            historyRow.view = historyView
            menu.addItem(historyRow)
            let source = NSMenu()
            let replacement = item("More", id: "more")
            replacement.submenu = NSMenu()
            replacement.submenu?.addItem(item("Settings updated", id: "settings"))
            source.addItem(replacement)
            let updatedHistory = item("", id: "history")
            updatedHistory.view = MenuBarUpdateHistoryView(
                history: MenuBarUpdateHistory(
                    buckets: [DashboardDayCount(day: .now, count: 2)]
                ))
            source.addItem(updatedHistory)

            NativeMenuUpdater.apply(source, to: menu)

            XCTAssertTrue(menu.items[0] === parent)
            XCTAssertTrue(parent.submenu === child)
            XCTAssertTrue(child.items.first === settings)
            XCTAssertEqual(settings.title, "Settings updated")
            XCTAssertTrue(historyRow.view === historyView)
            XCTAssertEqual(
                historyView.accessibilityValue() as? String, "2 updates. Daily counts: 2.")
        }

        private func item(_ title: String, id: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(id)
            return item
        }
    }

    @MainActor
    private final class TrackingRefreshDriver: NSObject, NSMenuDelegate {
        let menu = NSMenu()
        let row = NSMenuItem(title: "alpha — queued", action: nil, keyEquivalent: "")
        var isOpen = false
        var updatedWhileOpen = false

        override init() {
            super.init()
            row.identifier = NSUserInterfaceItemIdentifier("alpha")
            menu.addItem(row)
            menu.delegate = self
        }

        func menuWillOpen(_ menu: NSMenu) { isOpen = true }
        func menuDidClose(_ menu: NSMenu) { isOpen = false }

        @objc func refresh() {
            let source = NSMenu()
            let item = NSMenuItem(title: "alpha — updating…", action: nil, keyEquivalent: "")
            item.identifier = row.identifier
            source.addItem(item)
            NativeMenuUpdater.apply(source, to: menu)
            updatedWhileOpen = isOpen
            menu.cancelTracking()
        }
    }
#endif
