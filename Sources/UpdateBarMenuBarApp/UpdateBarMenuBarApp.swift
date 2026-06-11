#if os(macOS)
    import AppKit
    import Foundation
    import UpdateBarCore
    import UpdateBarMenuBar

    @main
    @MainActor
    final class UpdateBarMenuBarApp: NSObject, NSApplicationDelegate {
        private var statusItem: NSStatusItem!
        private var client: UpdateBarCLIClient!
        private let formatter = MenuBarStatusFormatter()
        private var latestState = MenuBarState(
            title: "Checking...",
            badgeValue: nil,
            outdatedItems: [],
            approvalItems: [],
            errorItems: [],
            okItems: []
        )
        private var approvalStatuses: [String: [CommandApprovalStatus]] = [:]

        static func main() {
            let app = NSApplication.shared
            let delegate = UpdateBarMenuBarApp()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            client = UpdateBarCLIClient(executablePath: Self.resolveCLIPath())
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.title = "UB"
            rebuildMenu()
            refreshStatus(refresh: false)
        }

        @objc private func checkNow() {
            runAction { [client] in
                try client?.checkNow()
            }
        }

        @objc private func updateAllApproved() {
            runAction { [client] in
                try client?.updateAllApproved()
            }
        }

        @objc private func updateSelected(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ItemAction else { return }
            let id = action.id
            runAction { [client] in
                try client?.update(id: id)
            }
        }

        @objc private func approveField(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ApprovalAction else { return }
            let id = action.id
            let field = action.field
            runAction { [client] in
                try client?.approve(id: id, field: field)
            }
        }

        @objc private func revokeField(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ApprovalAction else { return }
            let id = action.id
            let field = action.field
            runAction { [client] in
                try client?.revoke(id: id, field: field)
            }
        }

        @objc private func refreshFromMenu() {
            refreshStatus(refresh: true)
        }

        @objc private func revealManifest() {
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths().manifestFile])
        }

        @objc private func quit() {
            NSApplication.shared.terminate(nil)
        }

        private func refreshStatus(refresh: Bool) {
            setTitle("...")
            DispatchQueue.global(qos: .userInitiated).async { [client, formatter] in
                do {
                    guard let client else { return }
                    let snapshot = try client.status(refresh: refresh)
                    let state = formatter.makeState(from: snapshot)
                    var approvals: [String: [CommandApprovalStatus]] = [:]
                    for item in state.approvalItems {
                        approvals[item.id] = try client.approvals(id: item.id)
                    }
                    DispatchQueue.main.async {
                        self.latestState = state
                        self.approvalStatuses = approvals
                        self.rebuildMenu()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showError(error)
                    }
                }
            }
        }

        private func runAction(_ action: @escaping @Sendable () throws -> Void) {
            setTitle("...")
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try action()
                    DispatchQueue.main.async {
                        self.refreshStatus(refresh: false)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showError(error)
                    }
                }
            }
        }

        private func rebuildMenu() {
            setTitle(latestState.badgeValue ?? "UB")
            let menu = NSMenu()
            menu.addItem(disabledItem(latestState.title))
            if latestState.needsAttentionCount > 0 {
                menu.addItem(disabledItem("\(latestState.needsAttentionCount) need attention"))
            }
            menu.addItem(.separator())
            menu.addItem(actionItem("Check Now", action: #selector(refreshFromMenu)))
            menu.addItem(
                actionItem("Update All Approved Outdated", action: #selector(updateAllApproved)))
            menu.addItem(.separator())

            addSection("Updates", items: latestState.outdatedItems, to: menu) { item in
                let label = "\(item.name) \(item.current ?? "?") -> \(item.latest ?? "?")"
                let menuItem = actionItem(label, action: #selector(updateSelected(_:)))
                menuItem.representedObject = ItemAction(id: item.id)
                return menuItem
            }
            addApprovalSection(to: menu)
            addSection("Errors", items: latestState.errorItems, to: menu) { item in
                disabledItem("\(item.name): \(item.error ?? "error")")
            }
            addSection("Installed", items: latestState.okItems, to: menu) { item in
                disabledItem("\(item.name) \(item.current ?? "")")
            }

            menu.addItem(.separator())
            menu.addItem(actionItem("Reveal Manifest", action: #selector(revealManifest)))
            menu.addItem(disabledItem("Preferences"))
            menu.addItem(actionItem("Quit", action: #selector(quit)))
            statusItem.menu = menu
        }

        private func addApprovalSection(to menu: NSMenu) {
            guard !latestState.approvalItems.isEmpty else { return }
            menu.addItem(disabledItem("Needs Approval"))
            for item in latestState.approvalItems {
                let approvals = approvalStatuses[item.id] ?? []
                if approvals.isEmpty {
                    menu.addItem(disabledItem("\(item.name): no command fields"))
                    continue
                }
                for approval in approvals {
                    let selector =
                        approval.approved ? #selector(revokeField(_:)) : #selector(approveField(_:))
                    let verb = approval.approved ? "Revoke" : "Approve"
                    let action = actionItem(
                        "\(verb) \(approval.field) for \(item.name)", action: selector)
                    action.representedObject = ApprovalAction(id: item.id, field: approval.field)
                    menu.addItem(action)
                }
            }
            menu.addItem(.separator())
        }

        private func addSection(
            _ title: String,
            items: [StatusItem],
            to menu: NSMenu,
            makeItem: (StatusItem) -> NSMenuItem
        ) {
            guard !items.isEmpty else { return }
            menu.addItem(disabledItem(title))
            for item in items {
                menu.addItem(makeItem(item))
            }
            menu.addItem(.separator())
        }

        private func showError(_ error: Error) {
            setTitle("!")
            let menu = NSMenu()
            menu.addItem(disabledItem("UpdateBar Error"))
            menu.addItem(disabledItem(String(describing: error)))
            menu.addItem(.separator())
            menu.addItem(actionItem("Check Now", action: #selector(refreshFromMenu)))
            menu.addItem(actionItem("Reveal Manifest", action: #selector(revealManifest)))
            menu.addItem(actionItem("Quit", action: #selector(quit)))
            statusItem.menu = menu
        }

        private func setTitle(_ title: String) {
            statusItem.button?.title = title
        }

        private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        private func disabledItem(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }

        private static func resolveCLIPath() -> String {
            let environment = ProcessInfo.processInfo.environment
            if let override = environment["UPDATEBAR_CLI"], !override.isEmpty {
                return override
            }
            if let bundled = Bundle.main.resourceURL?.appendingPathComponent("updatebar"),
                FileManager.default.isExecutableFile(atPath: bundled.path)
            {
                return bundled.path
            }
            let paths =
                (environment["PATH"] ?? "")
                .split(separator: ":")
                .map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
            for directory in paths {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent("updatebar")
                    .path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
            return "/opt/homebrew/bin/updatebar"
        }
    }

    private final class ItemAction: NSObject {
        let id: String

        init(id: String) {
            self.id = id
        }
    }

    private final class ApprovalAction: NSObject {
        let id: String
        let field: String

        init(id: String, field: String) {
            self.id = id
            self.field = field
        }
    }
#else
    import Foundation

    @main
    enum UpdateBarMenuBarUnsupported {
        static func main() {
            FileHandle.standardError.write(
                Data("updatebar-menubar is only supported on macOS\n".utf8))
        }
    }
#endif
