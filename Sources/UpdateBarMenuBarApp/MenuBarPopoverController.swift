#if os(macOS)
    import AppKit
    import SwiftUI
    import UpdateBarMenuBar

    @MainActor
    final class MenuBarPopoverController {
        private static let contentSize = NSSize(width: 390, height: 560)

        struct Callbacks {
            let onItemAction: (MenuBarPopoverRow) -> Void
            let onMenuAction: (MenuBarMenuAction) -> Void
            let onAbout: () -> Void
        }

        private let popover: NSPopover

        init() {
            popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = Self.contentSize
        }

        var isShown: Bool {
            popover.isShown
        }

        @discardableResult
        func toggle(
            relativeTo button: NSStatusBarButton,
            model: MenuBarPopoverModel,
            callbacks: Callbacks
        ) -> Bool {
            if popover.isShown {
                close()
                return true
            }
            guard button.window != nil else {
                return false
            }

            update(model: model, callbacks: callbacks)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            return popover.isShown
        }

        func update(model: MenuBarPopoverModel, callbacks: Callbacks) {
            let hostingView = NSHostingView(
                rootView: MenuBarPopoverView(
                    model: model,
                    onItemAction: callbacks.onItemAction,
                    onMenuAction: callbacks.onMenuAction,
                    onAbout: callbacks.onAbout
                ))
            hostingView.translatesAutoresizingMaskIntoConstraints = false

            let effectView = NSVisualEffectView()
            effectView.material = .popover
            effectView.blendingMode = .behindWindow
            effectView.state = .followsWindowActiveState
            effectView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            ])

            let contentViewController = NSViewController()
            contentViewController.view = effectView
            popover.contentViewController = contentViewController
            popover.contentSize = Self.contentSize
        }

        func close() {
            popover.performClose(nil)
        }
    }
#endif
