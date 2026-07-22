#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI
    import UpdateBarCore
    import UpdateBarMenuBar

    final class DashboardPanelController: NSWindowController, NSWindowDelegate {
        private let service: any MenuBarServicing
        private let model = DashboardModel()
        private var navigationModel = DashboardNavigationModel()
        private let splitViewController = NSSplitViewController()
        private let sidebarViewController = DashboardSidebarViewController()
        private let contentContainerViewController = NSViewController()
        private let overviewViewController = NSViewController()
        private let overviewHostingView: NSHostingView<AnyView> = NSHostingView(
            rootView: AnyView(ProgressView().frame(minWidth: 620, minHeight: 420))
        )
        private let manageItemsViewController: ManageItemsViewController
        private let scanViewController: ScanViewController
        private weak var visibleContentViewController: NSViewController?
        private var reloadGeneration = 0
        private var dashboardErrorQueue = DashboardErrorQueue()

        init(
            service: any MenuBarServicing,
            onItemsChanged: @escaping () -> Void
        ) {
            self.service = service
            manageItemsViewController = ManageItemsViewController(
                service: service,
                onChanged: onItemsChanged
            )
            scanViewController = ScanViewController(service: service, onChanged: {})
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 840, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Dashboard"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 760, height: 420)
            super.init(window: window)
            window.delegate = self

            overviewViewController.view = overviewHostingView
            contentContainerViewController.view = NSView()
            let sidebarItem = NSSplitViewItem(
                sidebarWithViewController: sidebarViewController
            )
            sidebarItem.minimumThickness = 150
            sidebarItem.maximumThickness = 190
            sidebarItem.canCollapse = false
            let contentItem = NSSplitViewItem(
                viewController: contentContainerViewController
            )
            splitViewController.addSplitViewItem(sidebarItem)
            splitViewController.addSplitViewItem(contentItem)
            window.contentViewController = splitViewController

            scanViewController.onChanged = { [weak self] in
                guard let self else { return }
                self.reloadGeneration &+= 1
                onItemsChanged()
            }
            sidebarViewController.onSelectionChanged = { [weak self] section in
                self?.select(section)
            }
            manageItemsViewController.onRefresh = { [weak self] in
                self?.reload()
            }
            manageItemsViewController.onError = { [weak self] error in
                self?.showErrorIfShown(error)
            }
            scanViewController.onError = { [weak self] error in
                self?.presentDashboardError(error)
            }
            select(.overview)
        }

        required init?(coder: NSCoder) {
            nil
        }

        func showWindowAndReload(selecting section: DashboardSection) {
            select(section)
            showWindow(nil)
            window?.center()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            reload()
        }

        func reloadIfShown() {
            guard window?.isVisible == true else { return }
            reload()
        }

        func showErrorIfShown(_ error: Error) {
            guard window?.isVisible == true else { return }
            reloadGeneration &+= 1
            manageItemsViewController.showError(error)
            presentDashboardError(error)
        }

        func reload() {
            reloadGeneration &+= 1
            let generation = reloadGeneration
            manageItemsViewController.setLoading()
            DispatchQueue.global(qos: .userInitiated).async { [service, model] in
                do {
                    let now = Date()
                    let since = Calendar.current.date(byAdding: .day, value: -28, to: now)
                    let snapshot = try service.status(refresh: false)
                    let events = try service.history(since: since)
                    let summary = model.summary(snapshot: snapshot, events: events, now: now)
                    DispatchQueue.main.async {
                        guard generation == self.reloadGeneration else { return }
                        self.apply(summary)
                        self.manageItemsViewController.apply(items: snapshot.items)
                        self.scanViewController.applyRegisteredItems(snapshot.items)
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard generation == self.reloadGeneration else { return }
                        self.manageItemsViewController.showError(error)
                        self.presentDashboardError(error)
                    }
                }
            }
        }

        func windowWillClose(_ notification: Notification) {
            reloadGeneration &+= 1
            scanViewController.invalidateScanSession()
            dashboardErrorQueue.clear()
        }

        private func select(_ section: DashboardSection) {
            navigationModel.select(section)
            sidebarViewController.select(navigationModel.selectedSection)
            showContent(controller(for: navigationModel.selectedSection))
        }

        private func controller(for section: DashboardSection) -> NSViewController {
            switch section {
            case .overview:
                return overviewViewController
            case .items:
                return manageItemsViewController
            case .scan:
                return scanViewController
            }
        }

        private func showContent(_ controller: NSViewController) {
            guard visibleContentViewController !== controller else { return }
            visibleContentViewController?.view.removeFromSuperview()
            visibleContentViewController?.removeFromParent()

            contentContainerViewController.addChild(controller)
            let contentView = controller.view
            contentView.translatesAutoresizingMaskIntoConstraints = false
            contentContainerViewController.view.addSubview(contentView)
            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(
                    equalTo: contentContainerViewController.view.leadingAnchor),
                contentView.trailingAnchor.constraint(
                    equalTo: contentContainerViewController.view.trailingAnchor),
                contentView.topAnchor.constraint(
                    equalTo: contentContainerViewController.view.topAnchor),
                contentView.bottomAnchor.constraint(
                    equalTo: contentContainerViewController.view.bottomAnchor),
            ])
            visibleContentViewController = controller
        }

        private func apply(_ summary: DashboardSummary) {
            let view = DashboardOverviewView(summary: summary)
            overviewHostingView.rootView = AnyView(view)
        }

        private func presentDashboardError(_ error: Error) {
            guard let window, window.isVisible else { return }
            dashboardErrorQueue.enqueue(
                SecretRedactor.redact(String(describing: error))
            )
            presentNextDashboardErrorIfPossible()
        }

        private func presentNextDashboardErrorIfPossible() {
            guard let window, window.isVisible, window.attachedSheet == nil,
                let presentation = dashboardErrorQueue.beginNextPresentation()
            else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "UpdateBar"
            alert.informativeText = presentation.message
            alert.beginSheetModal(for: window) { [weak self] _ in
                guard let self,
                    self.dashboardErrorQueue.finishPresentation(token: presentation.token)
                else { return }
                self.presentNextDashboardErrorIfPossible()
            }
        }
    }
#endif
