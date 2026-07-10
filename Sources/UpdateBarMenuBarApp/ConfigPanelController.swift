#if os(macOS)
    import AppKit
    import Foundation
    import UpdateBarCore
    import UpdateBarMenuBar

    final class ConfigPanelController: NSWindowController {
        private let service: any MenuBarServicing
        private let onSaved: () -> Void

        private let intervalField = NSTextField(string: "")
        private let requireHTTPSButton = NSButton(
            checkboxWithTitle: "Require HTTPS sources",
            target: nil,
            action: nil
        )
        private let saveButton = NSButton(title: "Save", target: nil, action: nil)
        private let reloadButton = NSButton(title: "Reload", target: nil, action: nil)
        private let statusLabel = NSTextField(labelWithString: "Ready")

        init(
            service: any MenuBarServicing,
            onSaved: @escaping () -> Void
        ) {
            self.service = service
            self.onSaved = onSaved
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 210),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "UpdateBar Config"
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 420, height: 190)
            super.init(window: panel)
            buildInterface()
        }

        required init?(coder: NSCoder) {
            nil
        }

        func showWindowAndLoad() {
            showWindow(nil)
            window?.center()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            load()
        }

        @objc private func load() {
            setRunning(true, message: "Loading...")
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    let config = try service.loadConfig()
                    DispatchQueue.main.async {
                        self.apply(config)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.finishWithError(error)
                    }
                }
            }
        }

        @objc private func save() {
            do {
                var config = Config.default
                try config.set(
                    "refresh.interval",
                    value: intervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                try config.set(
                    "security.require_https_source",
                    value: requireHTTPSButton.state == .on ? "true" : "false"
                )
                let configToSave = config
                setRunning(true, message: "Saving...")
                DispatchQueue.global(qos: .userInitiated).async { [service] in
                    do {
                        try service.saveConfig(configToSave)
                        DispatchQueue.main.async {
                            self.setRunning(false, message: "Saved.")
                            self.onSaved()
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.finishWithError(error)
                        }
                    }
                }
            } catch {
                finishWithError(error)
            }
        }

        private func buildInterface() {
            let intervalLabel = NSTextField(labelWithString: "Refresh interval")
            intervalField.placeholderString = "6h"
            intervalField.toolTip = "Examples: 30m, 6h, 1d"

            saveButton.target = self
            saveButton.action = #selector(save)
            reloadButton.target = self
            reloadButton.action = #selector(load)
            statusLabel.lineBreakMode = .byTruncatingTail

            let grid = NSGridView(views: [
                [intervalLabel, intervalField],
                [NSView(), requireHTTPSButton],
            ])
            grid.column(at: 0).xPlacement = .trailing
            grid.column(at: 1).xPlacement = .fill
            grid.rowSpacing = 10
            grid.columnSpacing = 12

            let buttons = NSStackView(views: [reloadButton, saveButton, statusLabel])
            buttons.orientation = .horizontal
            buttons.alignment = .centerY
            buttons.spacing = 8
            statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let stack = NSStackView(views: [grid, buttons])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false
            grid.translatesAutoresizingMaskIntoConstraints = false
            buttons.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.addSubview(stack)
            window?.contentView = content
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                stack.bottomAnchor.constraint(
                    lessThanOrEqualTo: content.bottomAnchor, constant: -16),
                grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
                buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
                intervalField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            ])
        }

        private func apply(_ config: Config) {
            intervalField.stringValue = config.refresh.interval.description
            requireHTTPSButton.state = config.security.requireHTTPSSource ? .on : .off
            setRunning(false, message: "Loaded.")
        }

        private func finishWithError(_ error: Error) {
            setRunning(false, message: SecretRedactor.redact(String(describing: error)))
            present(error)
        }

        private func setRunning(_ running: Bool, message: String) {
            intervalField.isEnabled = !running
            requireHTTPSButton.isEnabled = !running
            saveButton.isEnabled = !running
            reloadButton.isEnabled = !running
            statusLabel.stringValue = SecretRedactor.redact(message)
        }

        private func present(_ error: Error) {
            guard let window else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "UpdateBar"
            alert.informativeText = SecretRedactor.redact(String(describing: error))
            alert.beginSheetModal(for: window)
        }
    }
#endif
