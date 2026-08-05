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

            XCTAssertEqual(tableView.numberOfRows, 5)
            XCTAssertEqual(tableView.selectedRow, 4)
            XCTAssertEqual(
                (controller.tableView(tableView, viewFor: nil, row: 3)?.accessibilityLabel()),
                "Settings"
            )
            XCTAssertEqual(
                (controller.tableView(tableView, viewFor: nil, row: 4)?.accessibilityLabel()),
                "About"
            )
        }

        func testUpdateQueueSelectionRoutesToCallbackWithoutUpdating() {
            let controller = DashboardSidebarViewController()
            var selectedIDs: [String] = []
            controller.onUpdateSelected = { selectedIDs.append($0) }

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

            controller.selectUpdate(id: "brew")

            XCTAssertEqual(selectedIDs, ["brew"])
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
    }
#endif
