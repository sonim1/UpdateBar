#if os(macOS)
    import AppKit
    import SwiftUI
    import UpdateBarCore
    import UpdateBarMenuBar

    final class SettingsViewController: NSViewController {
        private let service: any MenuBarServicing
        let model: SettingsViewModel
        private let onSaved: () -> Void
        private var loadedConfig: Config?

        init(
            service: any MenuBarServicing,
            onSaved: @escaping () -> Void,
            onCheckForUpdates: @escaping () -> Void
        ) {
            self.service = service
            self.onSaved = onSaved
            let version =
                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "—"
            let build =
                Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                ?? "—"
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
            guard !model.isRunning else { return }
            model.isRunning = true
            model.status = "Loading..."
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    let config = try service.loadConfig()
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        apply(config)
                        model.isRunning = false
                        model.status = "Loaded."
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in self?.finish(error) }
                }
            }
        }

        private func save() {
            guard !model.isRunning, let loadedConfig else { return }
            let changes = [
                (
                    "refresh.interval",
                    model.refreshInterval.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                ("security.require_https_source", String(model.requireHTTPS)),
                ("update.max_concurrent", String(model.maxConcurrent)),
            ].filter { loadedConfig.get($0.0) != $0.1 }
            model.isRunning = true
            model.status = "Saving..."
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    var config = try service.loadConfig()
                    for (key, value) in changes {
                        try config.set(key, value: value)
                    }
                    if !changes.isEmpty {
                        try service.saveConfig(config)
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        apply(config)
                        model.isRunning = false
                        model.status = "Saved."
                        onSaved()
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in self?.finish(error) }
                }
            }
        }

        private func apply(_ config: Config) {
            loadedConfig = config
            model.refreshInterval = config.refresh.interval.description
            model.requireHTTPS = config.security.requireHTTPSSource
            model.maxConcurrent = config.update.maxConcurrent
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
