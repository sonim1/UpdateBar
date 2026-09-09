#if os(macOS)
    import AppKit
    import UpdateBarCore
    import UpdateBarMenuBar
    import XCTest

    @testable import UpdateBarMenuBarApp

    @MainActor
    final class MenuBarPopoverControllerTests: XCTestCase {
        func testApprovalRequiresAcknowledgementAndNeverStartsUpdate() {
            var approved: CommandApprovalStatus?
            var updateCalls = 0
            var actions = actions()
            actions.setApproval = { id, command, value in
                XCTAssertEqual(id, "tool")
                XCTAssertTrue(value)
                approved = command
            }
            actions.update = { _ in updateCalls += 1 }
            let store = MenuBarPopoverStore(actions: actions)
            let command = CommandApprovalStatus(
                field: "update.cmd", approved: false, fingerprint: "reviewed-fingerprint",
                command: "tool update", cwd: "/working directory"
            )
            store.model.update(state: state(), approvals: ["tool": [command]])

            store.setApproval(id: "tool", field: command.field)
            XCTAssertNil(approved)
            store.model.setAcknowledged(true, id: "tool", field: command.field)
            store.setApproval(id: "tool", field: command.field)

            XCTAssertEqual(approved, command)
            XCTAssertEqual(updateCalls, 0)
            XCTAssertFalse(store.model.isAcknowledged(id: "tool", field: command.field))
        }

        func testBusyStoreBlocksMutationAndKeepsDashboardAvailable() {
            var mutationCalls = 0
            var dashboardSection: DashboardSection?
            var actions = actions()
            actions.check = { mutationCalls += 1 }
            actions.update = { _ in mutationCalls += 1 }
            actions.retry = { _ in mutationCalls += 1 }
            actions.stop = { mutationCalls += 1 }
            actions.setApproval = { _, _, _ in mutationCalls += 1 }
            actions.dashboard = { dashboardSection = $0 }
            let store = MenuBarPopoverStore(actions: actions)
            store.model.update(state: state(), approvals: [:], activeActionTitle: "Check Now")

            store.check()
            store.updateSelected()
            store.retryFailed()
            store.stop()
            store.setApproval(id: "tool", field: "update.cmd")
            store.dashboard(.items)

            XCTAssertEqual(mutationCalls, 0)
            XCTAssertEqual(dashboardSection, .items)
        }

        func testUnsupportedStoppingDoesNotDispatchStopAndDefaultStillDoes() {
            var stopCalls = 0
            var actions = actions()
            actions.stop = { stopCalls += 1 }
            let unsupported = MenuBarPopoverStore(actions: actions, supportsStopping: false)
            unsupported.model.update(
                state: state(), approvals: [:], activeActionTitle: "Updating items",
                isUpdateAction: true
            )

            unsupported.stop()
            XCTAssertEqual(stopCalls, 0)
            XCTAssertFalse(unsupported.supportsStopping)

            let supported = MenuBarPopoverStore(actions: actions)
            supported.model.update(
                state: state(), approvals: [:], activeActionTitle: "Updating items",
                isUpdateAction: true
            )
            supported.stop()
            XCTAssertEqual(stopCalls, 1)
            XCTAssertTrue(supported.supportsStopping)
        }

        func testRefreshAndCloseRetainHostingControllerSelectionAndDetails() {
            _ = NSApplication.shared
            let controller = MenuBarPopoverController(actions: actions())
            let host = controller.hostingController
            let store = controller.store
            refresh(controller)
            store.model.setSelected(false, id: "tool")
            store.model.showDetails(id: "tool")

            controller.close()
            refresh(controller)

            XCTAssertTrue(controller.hostingController === host)
            XCTAssertTrue(controller.store === store)
            XCTAssertTrue(store.model.selectedIDs.isEmpty)
            XCTAssertEqual(store.model.detailItemID, "tool")
            XCTAssertEqual(controller.popover.behavior, .transient)
        }

        func testEscapeClosesFromDetailsWithoutResettingNavigation() {
            let store = MenuBarPopoverStore(actions: actions())
            var closed = false
            store.close = { closed = true }
            store.model.update(state: state(), approvals: [:])
            store.model.showDetails(id: "tool")

            store.escape()

            XCTAssertTrue(closed)
            XCTAssertEqual(store.model.detailItemID, "tool")
        }

        func testPopoverFitsVisibleScreenAndCapsNormalSize() {
            XCTAssertEqual(
                MenuBarPopoverController.contentSize(
                    in: NSRect(x: 0, y: 0, width: 1440, height: 900)
                ),
                NSSize(width: 392, height: 560)
            )
            let constrained = MenuBarPopoverController.contentSize(
                in: NSRect(x: 0, y: 0, width: 300, height: 280)
            )
            XCTAssertLessThan(constrained.width, 300)
            XCTAssertLessThan(constrained.height, 280)
        }

        func testVisiblePopoverPreservesScrollUntilExplicitNavigationAndStaysBounded() throws {
            _ = NSApplication.shared
            let controller = MenuBarPopoverController(actions: actions())
            var snapshot = state()
            snapshot.allItems = (0..<16).map { index in
                var item = snapshot.outdatedItems[0]
                item.id = "tool-\(index)"
                item.name = "Tool \(index)"
                return item
            }
            snapshot.outdatedItems = snapshot.allItems
            let approvals = [
                "tool-0": ["check.cmd", "latest.cmd", "update.cmd"].map { field in
                    CommandApprovalStatus(
                        field: field, approved: false, fingerprint: field,
                        command: "tool --example-path '/a working directory/with spaces'",
                        cwd: "/a working directory/with spaces"
                    )
                }
            ]
            controller.update(
                state: snapshot, approvals: approvals, progress: MenuBarItemProgress(),
                activeActionTitle: nil, isUpdateAction: false, isRefreshing: false,
                stopRequested: false, notice: nil, errorMessage: nil
            )
            let anchorWindow = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 480, height: 240),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            anchorWindow.isReleasedWhenClosed = false
            let anchor = NSButton(frame: NSRect(x: 16, y: 180, width: 32, height: 32))
            anchorWindow.contentView?.addSubview(anchor)
            anchorWindow.orderFront(nil)
            controller.popover.contentSize = NSSize(width: 392, height: 560)
            controller.popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
            defer {
                controller.close()
                anchorWindow.close()
            }
            settleLayout(controller)
            let scroll = try XCTUnwrap(scrollView(in: controller.hostingController.view))
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
            scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertEqual(scroll.contentView.bounds.minY, 120, accuracy: 1)

            controller.update(
                state: snapshot, approvals: approvals, progress: MenuBarItemProgress(),
                activeActionTitle: "Checking for updates", isUpdateAction: false,
                isRefreshing: false, stopRequested: false, notice: nil, errorMessage: nil
            )
            settleLayout(controller)

            XCTAssertLessThanOrEqual(controller.popover.contentSize.width, 392)
            XCTAssertLessThanOrEqual(controller.popover.contentSize.height, 560)
            XCTAssertLessThanOrEqual(controller.hostingController.view.frame.height, 560)
            XCTAssertTrue(scrollView(in: controller.hostingController.view) === scroll)
            XCTAssertEqual(scroll.contentView.bounds.minY, 120, accuracy: 1)
            XCTAssertGreaterThan(
                try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height
            )

            controller.store.model.showDetails(id: "tool-0")
            settleLayout(controller)
            let detailScroll = try XCTUnwrap(scrollView(in: controller.hostingController.view))
            XCTAssertEqual(detailScroll.contentView.bounds.minY, 0, accuracy: 1)

            detailScroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
            detailScroll.reflectScrolledClipView(detailScroll.contentView)
            controller.update(
                state: snapshot, approvals: approvals, progress: MenuBarItemProgress(),
                activeActionTitle: nil, isUpdateAction: false, isRefreshing: true,
                stopRequested: false, notice: nil, errorMessage: nil
            )
            settleLayout(controller)
            XCTAssertTrue(scrollView(in: controller.hostingController.view) === detailScroll)
            XCTAssertEqual(detailScroll.contentView.bounds.minY, 120, accuracy: 1)
        }

        private func settleLayout(_ controller: MenuBarPopoverController) {
            controller.hostingController.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            controller.hostingController.view.layoutSubtreeIfNeeded()
        }

        private func scrollView(in root: NSView) -> NSScrollView? {
            if let scrollView = root as? NSScrollView { return scrollView }
            return root.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
        }

        private func refresh(_ controller: MenuBarPopoverController) {
            controller.update(
                state: state(), approvals: [:], progress: MenuBarItemProgress(),
                activeActionTitle: nil, isUpdateAction: false, isRefreshing: false,
                stopRequested: false, notice: nil, errorMessage: nil
            )
        }

        private func state() -> MenuBarState {
            let item = StatusItem(
                id: "tool", name: "Tool", category: "cli", current: "1.0", latest: "2.0",
                status: .outdated, pinned: false, lastChecked: nil, error: nil
            )
            return MenuBarState(
                title: "1 update", badgeValue: "1", outdatedItems: [item], approvalItems: [],
                errorItems: [], okItems: [], allItems: [item]
            )
        }

        private func actions() -> MenuBarPopoverActions {
            MenuBarPopoverActions(
                check: {}, update: { _ in }, retry: { _ in }, setApproval: { _, _, _ in },
                stop: {}, dashboard: { _ in }, more: {}
            )
        }
    }
#endif
