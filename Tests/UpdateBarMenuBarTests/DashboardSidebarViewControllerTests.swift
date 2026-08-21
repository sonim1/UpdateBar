#if os(macOS)
    import AppKit
    import UpdateBarMenuBar
    @testable import UpdateBarMenuBarApp
    import XCTest

    @MainActor
    final class DashboardSidebarViewControllerTests: XCTestCase {
        func testSelectingItemsEmitsOnceAndPreservesSelectedRow() throws {
            let controller = DashboardSidebarViewController()
            _ = controller.view
            let tableView = try XCTUnwrap(findTableView(in: controller.view))
            var selections: [DashboardSection] = []
            controller.onSelectionChanged = { selections.append($0) }

            tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

            XCTAssertEqual(selections, [.items])
            XCTAssertEqual(tableView.selectedRow, 1)
            XCTAssertEqual(tableView.accessibilitySelectedRows()?.count, 1)
        }

        func testInitialProgrammaticSelectionDoesNotEmitCallback() throws {
            let controller = DashboardSidebarViewController(selectedSection: .items)
            var selections: [DashboardSection] = []
            controller.onSelectionChanged = { selections.append($0) }

            _ = controller.view
            let tableView = try XCTUnwrap(findTableView(in: controller.view))

            XCTAssertEqual(selections, [])
            XCTAssertEqual(tableView.selectedRow, 1)
            XCTAssertEqual(tableView.accessibilitySelectedRows()?.count, 1)
        }

        func testSelectingScanEmitsOnceAndPreservesSelectedRow() throws {
            let controller = DashboardSidebarViewController()
            _ = controller.view
            let tableView = try XCTUnwrap(findTableView(in: controller.view))
            var selections: [DashboardSection] = []
            controller.onSelectionChanged = { selections.append($0) }

            tableView.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)

            XCTAssertEqual(selections, [.scan])
            XCTAssertEqual(tableView.selectedRow, 2)
            XCTAssertEqual(tableView.accessibilitySelectedRows()?.count, 1)
        }

        func testProgrammaticSelectionSuppressesCallback() throws {
            let controller = DashboardSidebarViewController()
            _ = controller.view
            let tableView = try XCTUnwrap(findTableView(in: controller.view))
            var selections: [DashboardSection] = []
            controller.onSelectionChanged = { selections.append($0) }

            controller.select(.scan)

            XCTAssertEqual(selections, [])
            XCTAssertEqual(tableView.selectedRow, 2)
            XCTAssertEqual(tableView.accessibilitySelectedRows()?.count, 1)
        }

        func testSidebarIncludesSettingsAndAboutSections() throws {
            let controller = DashboardSidebarViewController(selectedSection: .about)

            _ = controller.view
            let tableView = try XCTUnwrap(findTableView(in: controller.view))

            XCTAssertEqual(tableView.numberOfRows, 6)
            XCTAssertEqual(tableView.selectedRow, 5)
            XCTAssertEqual(
                (controller.tableView(tableView, viewFor: nil, row: 3)?.accessibilityLabel()),
                "Logs"
            )
            XCTAssertEqual(
                (controller.tableView(tableView, viewFor: nil, row: 4)?.accessibilityLabel()),
                "Settings"
            )
            XCTAssertEqual(
                (controller.tableView(tableView, viewFor: nil, row: 5)?.accessibilityLabel()),
                "About"
            )
        }

        func testUpdateQueueRendersOneBoundedSummaryButton() throws {
            let controller = DashboardSidebarViewController()
            _ = controller.view
            controller.view.frame = NSRect(x: 0, y: 0, width: 150, height: 420)
            controller.apply(
                updateQueue: SidebarUpdateQueue(
                    count: 12,
                    items: [
                        SidebarUpdateQueueItem(
                            id: "long",
                            title: "A Library Name That Must Never Control Sidebar Width",
                            versionChange: "123.456.789 → 987.654.321"
                        )
                    ],
                    overflowCount: 11
                )
            )
            controller.view.layoutSubtreeIfNeeded()

            let buttons = findButtons(in: controller.view).filter {
                $0.identifier?.rawValue == "sidebar-updates-summary"
            }
            let button = try XCTUnwrap(buttons.first)
            let title = try XCTUnwrap(
                findTextFields(in: button).first {
                    $0.identifier?.rawValue == "sidebar-updates-title"
                })
            let detail = try XCTUnwrap(
                findTextFields(in: button).first {
                    $0.identifier?.rawValue == "sidebar-updates-detail"
                })

            XCTAssertEqual(buttons.count, 1)
            XCTAssertEqual(title.stringValue, "Updates available")
            XCTAssertEqual(detail.stringValue, "12 items · Open Items")
            XCTAssertLessThanOrEqual(button.frame.maxX, try XCTUnwrap(button.superview).bounds.maxX)
            XCTAssertGreaterThanOrEqual(button.frame.minX, 0)
            XCTAssertEqual(button.accessibilityLabel(), "Open Items, 12 updates available")
            XCTAssertEqual(
                button.accessibilityHelp(),
                "Shows the Items section without starting an update"
            )

            controller.view.frame.size.width = 190
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(button.frame.maxX, try XCTUnwrap(button.superview).bounds.maxX)
        }

        func testEmptyUpdateQueueRendersNoSummaryButton() {
            let controller = DashboardSidebarViewController()
            _ = controller.view

            controller.apply(updateQueue: SidebarUpdateQueue(count: 0, items: [], overflowCount: 0))

            XCTAssertFalse(
                findButtons(in: controller.view).contains {
                    $0.identifier?.rawValue == "sidebar-updates-summary"
                })
        }

        func testUpdateSummaryRoutesToItemsWithoutUpdating() throws {
            let controller = DashboardSidebarViewController()
            _ = controller.view
            var openCount = 0
            controller.onOpenItems = { openCount += 1 }
            controller.apply(
                updateQueue: SidebarUpdateQueue(
                    count: 2,
                    items: [
                        SidebarUpdateQueueItem(
                            id: "brew",
                            title: "Homebrew",
                            versionChange: "1 → 2"
                        )
                    ],
                    overflowCount: 1
                )
            )
            let button = try XCTUnwrap(
                findButtons(in: controller.view).first {
                    $0.identifier?.rawValue == "sidebar-updates-summary"
                })

            button.performClick(nil)

            XCTAssertEqual(openCount, 1)
        }

        private func findTableView(in view: NSView) -> NSTableView? {
            if let tableView = view as? NSTableView {
                return tableView
            }
            for subview in view.subviews {
                if let tableView = findTableView(in: subview) {
                    return tableView
                }
            }
            return nil
        }

        private func findButtons(in view: NSView) -> [NSButton] {
            var result: [NSButton] = []
            if let button = view as? NSButton {
                result.append(button)
            }
            for subview in view.subviews {
                result.append(contentsOf: findButtons(in: subview))
            }
            return result
        }

        private func findTextFields(in view: NSView) -> [NSTextField] {
            var result: [NSTextField] = []
            if let textField = view as? NSTextField {
                result.append(textField)
            }
            for subview in view.subviews {
                result.append(contentsOf: findTextFields(in: subview))
            }
            return result
        }
    }
#endif
