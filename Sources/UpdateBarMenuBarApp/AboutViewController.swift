#if os(macOS)
    import AppKit
    import SwiftUI

    final class AboutViewController: NSViewController {
        override func loadView() {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            let view = AboutView(
                version: version,
                build: build,
                onSupport: {
                    guard let url = URL(string: "mailto:support@updatebar.royjen.com") else { return }
                    NSWorkspace.shared.open(url)
                },
                onAcknowledgments: { [weak self] in self?.showAcknowledgments() }
            )
            let hosting = NSHostingController(rootView: view)
            addChild(hosting)
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            let content = NSView()
            content.addSubview(hosting.view)
            NSLayoutConstraint.activate([
                hosting.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                hosting.view.topAnchor.constraint(equalTo: content.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
            self.view = content
        }

        private func showAcknowledgments() {
            let alert = NSAlert()
            alert.messageText = "Acknowledgments"
            alert.informativeText = "Built with Swift, AppKit, SwiftUI, Sparkle, and UpdateBar Core."
            if let window = view.window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }
#endif
