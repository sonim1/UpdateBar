#if os(macOS)
    import AppKit
    import SwiftUI
    import UpdateBarMenuBar

    @MainActor
    final class DashboardPopoverController {
        private let popover = NSPopover()
        private let hostingView: NSHostingView<AnyView>
        private let effectView: NSVisualEffectView

        init() {
            hostingView = NSHostingView(rootView: AnyView(EmptyView()))
            effectView = NSVisualEffectView(
                frame: NSRect(origin: .zero, size: DashboardPopoverLayout.size)
            )

            popover.behavior = .transient
            popover.contentSize = DashboardPopoverLayout.size

            effectView.material = .popover
            effectView.blendingMode = .behindWindow
            effectView.state = .followsWindowActiveState

            hostingView.frame = effectView.bounds
            hostingView.autoresizingMask = [.width, .height]
            effectView.addSubview(hostingView)

            let contentViewController = NSViewController()
            contentViewController.view = effectView
            popover.contentViewController = contentViewController
        }

        var isShown: Bool {
            popover.isShown
        }

        func show(
            relativeTo anchorView: NSView,
            model: DashboardPopoverModel,
            onOpenFullDashboard: @escaping () -> Void
        ) {
            update(model: model, onOpenFullDashboard: onOpenFullDashboard)
            popover.show(
                relativeTo: anchorView.bounds,
                of: anchorView,
                preferredEdge: .minY
            )
        }

        func update(
            model: DashboardPopoverModel,
            onOpenFullDashboard: @escaping () -> Void
        ) {
            hostingView.rootView = AnyView(
                DashboardPopoverView(
                    model: model,
                    onOpenFullDashboard: onOpenFullDashboard
                )
            )
        }

        func close() {
            popover.close()
        }
    }
#endif
