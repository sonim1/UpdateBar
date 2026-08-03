#if os(macOS)
    import AppKit
    import SwiftUI
    import UpdateBarCore
    import UpdateBarMenuBar

    final class SettingsViewController: NSViewController {
        private let service: any MenuBarServicing
        private let model: SettingsViewModel
        private let onSaved: () -> Void

        init(
            service: any MenuBarServicing,
            onSaved: @escaping () -> Void,
            onCheckForUpdates: @escaping () -> Void
        ) {
            self.service = service
            self.onSaved = onSaved
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
            model = SettingsViewModel(
                version: version,
                build: build,
                onReload: {},
                onSave: {},
                onCheckForUpdates: onCheckForUpdates
            )
            super.init(nibName: nil, bundle: nil)
            model.onReload = { [weak self] in self?.load() }
            model.onSave = { [weak self] in self?.save() }
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
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
            view = content
        }

        func prepare() {
            load()
        }

        private func load() {
            model.isRunning = true
            model.status = "Loading..."
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    let config = try service.loadConfig()
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        model.refreshInterval = config.refresh.interval.description
                        model.requireHTTPS = config.security.requireHTTPSSource
                        model.isRunning = false
                        model.status = "Loaded."
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in self?.finish(error) }
                }
            }
        }

        private func save() {
            do {
                var config = Config.default
                try config.set("refresh.interval", value: model.refreshInterval.trimmingCharacters(in: .whitespacesAndNewlines))
                try config.set("security.require_https_source", value: model.requireHTTPS ? "true" : "false")
                model.isRunning = true
                model.status = "Saving..."
                DispatchQueue.global(qos: .userInitiated).async { [service] in
                    do {
                        try service.saveConfig(config)
                        DispatchQueue.main.async { [weak self] in
                            self?.model.isRunning = false
                            self?.model.status = "Saved."
                            self?.onSaved()
                        }
                    } catch {
                        DispatchQueue.main.async { [weak self] in self?.finish(error) }
                    }
                }
            } catch {
                finish(error)
            }
        }

        private func finish(_ error: Error) {
            model.isRunning = false
            model.status = SecretRedactor.redact(String(describing: error))
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "UpdateBar"
            alert.informativeText = model.status
            if let window = view.window { alert.beginSheetModal(for: window) }
        }
    }
#endif
