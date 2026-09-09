#if os(macOS)
    import AppKit
    import SwiftUI
    import UpdateBarMenuBar

    @MainActor
    struct MenuBarPopoverActions {
        var check: () -> Void
        var update: ([String]) -> Void
        var retry: ([String]) -> Void
        var setApproval: (String, CommandApprovalStatus, Bool) -> Void
        var stop: () -> Void
        var dashboard: (DashboardSection) -> Void
        var more: () -> Void
    }

    @MainActor
    final class MenuBarPopoverStore: ObservableObject {
        @Published var model = MenuBarPopoverModel()
        let supportsStopping: Bool
        var close: () -> Void = {}
        private let actions: MenuBarPopoverActions

        init(actions: MenuBarPopoverActions, supportsStopping: Bool = true) {
            self.actions = actions
            self.supportsStopping = supportsStopping
        }

        func check() {
            guard !model.isBusy else { return }
            actions.check()
        }

        func updateSelected() {
            guard !model.isBusy, !model.selectedIDs.isEmpty else { return }
            actions.update(model.selectedIDs)
        }

        func retryFailed() {
            guard !model.isBusy, !model.retryIDs.isEmpty else { return }
            actions.retry(model.retryIDs)
        }

        func setApproval(id: String, field: String) {
            guard let reviewed = model.reviewedApproval(id: id, field: field) else { return }
            model.setAcknowledged(false, id: id, field: field)
            actions.setApproval(id, reviewed, !reviewed.approved)
        }

        func stop() {
            guard supportsStopping, model.isUpdating, !model.stopRequested else { return }
            actions.stop()
        }

        func dashboard(_ section: DashboardSection) {
            close()
            actions.dashboard(section)
        }

        func more() {
            close()
            actions.more()
        }

        func escape() {
            close()
        }
    }

    @MainActor
    final class MenuBarPopoverController {
        let store: MenuBarPopoverStore
        let hostingController: NSHostingController<MenuBarPopoverView>
        let popover = NSPopover()

        init(actions: MenuBarPopoverActions, supportsStopping: Bool = true) {
            let store = MenuBarPopoverStore(actions: actions, supportsStopping: supportsStopping)
            self.store = store
            self.hostingController = NSHostingController(rootView: MenuBarPopoverView(store: store))
            hostingController.sizingOptions = []
            popover.behavior = .transient
            popover.animates = false
            popover.contentViewController = hostingController
            popover.contentSize = NSSize(width: 392, height: 560)
            store.close = { [weak self] in self?.close() }
        }

        var isShown: Bool { popover.isShown }

        func toggle(relativeTo button: NSStatusBarButton) {
            guard !isShown else {
                close()
                return
            }
            if let screen = button.window?.screen ?? NSScreen.main {
                popover.contentSize = Self.contentSize(in: screen.visibleFrame)
            }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            hostingController.view.window?.makeKey()
        }

        func close() {
            popover.performClose(nil)
        }

        func update(
            state: MenuBarState,
            approvals: [String: [CommandApprovalStatus]],
            progress: MenuBarItemProgress,
            activeActionTitle: String?,
            isUpdateAction: Bool,
            isRefreshing: Bool,
            stopRequested: Bool,
            notice: String?,
            errorMessage: String?
        ) {
            let finishedAction = store.model.activeActionTitle != nil && activeActionTitle == nil
            let finishedUpdate = store.model.isUpdating && finishedAction
            store.model.update(
                state: state,
                approvals: approvals,
                progress: progress,
                activeActionTitle: activeActionTitle,
                isUpdateAction: isUpdateAction,
                isRefreshing: isRefreshing,
                stopRequested: stopRequested,
                notice: notice,
                errorMessage: errorMessage
            )
            if finishedAction && isShown {
                let announcement: String
                if let error = store.model.errorMessage {
                    announcement = "Action failed. \(error)"
                } else if finishedUpdate && !progress.failedIDs.isEmpty {
                    announcement =
                        "\(progress.succeededIDs.count) updates succeeded. \(progress.failedIDs.count) failed."
                } else {
                    announcement = store.model.notice ?? "Action finished."
                }
                NSAccessibility.post(
                    element: hostingController.view,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: announcement,
                        .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                    ]
                )
            }
        }

        static func contentSize(in visibleFrame: NSRect) -> NSSize {
            NSSize(
                width: min(392, max(1, visibleFrame.width - 32)),
                height: min(560, max(1, visibleFrame.height - 32))
            )
        }
    }
#endif
