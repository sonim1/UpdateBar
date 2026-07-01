#if os(macOS)
    import AppKit
    import Foundation
    import UpdateBarCore
    import UpdateBarMenuBar

    @main
    @MainActor
    final class UpdateBarMenuBarApp: NSObject, NSApplicationDelegate {
        private static var bootstrapDelegate: UpdateBarMenuBarApp?
        private var statusItem: NSStatusItem!
        private var service: (any MenuBarServicing)!
        private var cliPath = ""
        private let formatter = MenuBarStatusFormatter()
        private let menuBuilder = MenuBarMenuModelBuilder()
        private let actionCoordinator = MenuBarActionCoordinator()
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
            bootstrapDelegate = delegate
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            debugLog("UpdateBarMenuBar main starting")
            app.run()
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            cliPath = Self.resolveCLIPath()
            Self.debugLog("resolved updatebar path: \(cliPath)")
            service = Self.makeService(cliPath: cliPath)
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.autosaveName = "UpdateBarStatusItem"
            statusItem.isVisible = true
            guard let statusButton = statusItem.button else {
                showError(MenuBarStartupError.missingStatusBarButton)
                return
            }

            statusButton.title = "UB"
            statusButton.toolTip = "UpdateBar"
            statusButton.setAccessibilityIdentifier("updatebar-status-button")
            statusButton.setAccessibilityLabel("UpdateBar status")
            if let image = NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath",
                accessibilityDescription: "UpdateBar"
            ) {
                image.isTemplate = true
                statusButton.image = image
                statusButton.imagePosition = .imageLeading
            }
            rebuildMenu()
            ProcessInfo.processInfo.disableAutomaticTermination("UpdateBar menu bar app running")
            refreshStatus(refresh: false)
        }

        func applicationWillTerminate(_ notification: Notification) {
            ProcessInfo.processInfo.enableAutomaticTermination("UpdateBar menu bar app terminated")
            Self.bootstrapDelegate = nil
        }

        @objc private func checkNow() {
            runAction("Check Now") { [service] token in
                try service?.checkNow(cancellationToken: token)
            }
        }

        @objc private func updateAllApproved() {
            runAction("Run Updates") { [service] token in
                try service?.updateAllApproved(cancellationToken: token)
            }
        }

        @objc private func updateSelected(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ItemAction else { return }
            let id = action.id
            runAction("Update \(id)") { [service] token in
                try service?.update(id: id, cancellationToken: token)
            }
        }

        @objc private func approveField(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ApprovalAction else { return }
            let id = action.id
            let field = action.field
            runAction("Approve \(id) \(field)") { [service] token in
                try service?.approve(id: id, field: field, cancellationToken: token)
            }
        }

        @objc private func revokeField(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ApprovalAction else { return }
            let id = action.id
            let field = action.field
            runAction("Revoke \(id) \(field)") { [service] token in
                try service?.revoke(id: id, field: field, cancellationToken: token)
            }
        }

        @objc private func refreshFromMenu() {
            refreshStatus(refresh: true)
        }

        @objc private func cancelCurrentAction() {
            guard actionCoordinator.cancelActive() != nil else { return }
            rebuildMenu()
        }

        @objc private func openTUI() {
            let command = OpenTUICommand(cliPath: cliPath)
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command.executablePath)
                process.arguments = command.arguments
                try process.run()
            } catch {
                showError(error)
            }
        }

        @objc private func openConfig() {
            NSWorkspace.shared.open(AppPaths().configFile)
        }

        @objc private func viewLogs() {
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths().homeDirectory])
        }

        @objc private func quit() {
            NSApplication.shared.terminate(nil)
        }

        private func refreshStatus(refresh: Bool) {
            setTitle("...", accessibilityLabel: "UpdateBar checking")
            DispatchQueue.global(qos: .userInitiated).async { [service, formatter] in
                do {
                    guard let service else { return }
                    let snapshot = try service.status(refresh: refresh)
                    var approvals: [String: [CommandApprovalStatus]] = [:]
                    for item in snapshot.items {
                        let itemApprovals = try service.approvals(id: item.id)
                        if !itemApprovals.isEmpty {
                            approvals[item.id] = itemApprovals
                        }
                    }
                    let state = formatter.makeState(
                        from: snapshot,
                        approvalsByItemID: approvals
                    )
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

        private func runAction(
            _ title: String,
            _ action: @escaping @Sendable (CancellationToken) throws -> Void
        ) {
            guard let activeAction = actionCoordinator.begin(title) else {
                rebuildMenu()
                return
            }
            rebuildMenu()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try action(activeAction.token)
                    DispatchQueue.main.async {
                        let wasCancelled = activeAction.token.isCancelled
                        self.actionCoordinator.finish(
                            activeAction,
                            outcome: wasCancelled ? .cancelled : .finished
                        )
                        if wasCancelled {
                            self.rebuildMenu()
                        } else {
                            self.refreshStatus(refresh: false)
                        }
                    }
                } catch let error as ExecutionError where error.isCancellation {
                    DispatchQueue.main.async {
                        self.actionCoordinator.finish(activeAction, outcome: .cancelled)
                        self.rebuildMenu()
                    }
                } catch let error as UpdateBarCLIClientError where error == .cancelled {
                    DispatchQueue.main.async {
                        self.actionCoordinator.finish(activeAction, outcome: .cancelled)
                        self.rebuildMenu()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.actionCoordinator.finish(activeAction, outcome: .failed)
                        self.showError(error)
                    }
                }
            }
        }

        private func rebuildMenu() {
            let activeAction = actionCoordinator.activeAction
            let lastActionNotice = actionCoordinator.lastActionNotice
            if let activeAction {
                setTitle("...", accessibilityLabel: "UpdateBar running \(activeAction.title)")
            } else {
                setTitle(
                    latestState.badgeValue ?? "UB",
                    accessibilityLabel: accessibilityLabel(for: latestState)
                )
            }
            let model = menuBuilder.makeMenu(
                state: latestState,
                approvalStatuses: approvalStatuses,
                activeActionTitle: activeAction?.title,
                lastActionNotice: activeAction == nil ? lastActionNotice : nil
            )
            statusItem.menu = makeMenu(from: model)
        }

        private func makeMenu(from model: MenuBarMenuModel) -> NSMenu {
            let menu = NSMenu()
            for entry in model.entries {
                switch entry {
                case .separator:
                    menu.addItem(.separator())
                case .item(let item):
                    menu.addItem(menuItem(from: item))
                }
            }
            return menu
        }

        private func menuItem(from item: MenuBarMenuItem) -> NSMenuItem {
            guard let action = item.action else {
                return disabledItem(item.title)
            }
            let menuItem = actionItem(item.title, action: selector(for: action))
            menuItem.toolTip = item.toolTip
            switch action {
            case .menu, .cancelCurrentAction:
                break
            case .update(let id):
                menuItem.representedObject = ItemAction(id: id)
            case .approve(let id, let field), .revoke(let id, let field):
                menuItem.representedObject = ApprovalAction(id: id, field: field)
            }
            return menuItem
        }

        private func showError(_ error: Error) {
            Self.debugLog("showing error: \(error)")
            setTitle("!", accessibilityLabel: "UpdateBar error")
            let model = menuBuilder.makeErrorMenu(
                errorDescription: String(describing: error)
            )
            statusItem.menu = makeMenu(from: model)
        }

        private func setTitle(_ title: String, accessibilityLabel: String? = nil) {
            statusItem.button?.title = title
            statusItem.button?.setAccessibilityLabel(accessibilityLabel ?? "UpdateBar \(title)")
        }

        private func accessibilityLabel(for state: MenuBarState) -> String {
            if state.needsAttentionCount > 0 {
                return "UpdateBar \(state.title), \(state.needsAttentionCount) need attention"
            }
            return "UpdateBar \(state.title)"
        }

        private static func debugLog(_ message: String) {
            FileHandle.standardError.write(Data(("UpdateBarMenuBar: \(message)\n").utf8))
        }

        private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        private func selector(for action: MenuBarMenuItemAction) -> Selector {
            switch action {
            case .menu(let menuAction):
                return selector(for: menuAction)
            case .cancelCurrentAction:
                return #selector(cancelCurrentAction)
            case .update:
                return #selector(updateSelected(_:))
            case .approve:
                return #selector(approveField(_:))
            case .revoke:
                return #selector(revokeField(_:))
            }
        }

        private func selector(for action: MenuBarMenuAction) -> Selector {
            switch action {
            case .checkNow:
                return #selector(checkNow)
            case .updateAllApprovedOutdated:
                return #selector(updateAllApproved)
            case .openTUI:
                return #selector(openTUI)
            case .openConfig:
                return #selector(openConfig)
            case .viewLogs:
                return #selector(viewLogs)
            case .quit:
                return #selector(quit)
            }
        }

        private func disabledItem(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = title
            return item
        }

        private static func resolveCLIPath() -> String {
            do {
                let resolution = try UpdateBarBinaryResolver().resolve(
                    bundledDirectory: Bundle.main.resourceURL
                )
                debugLog("using \(resolution.source.rawValue) updatebar: \(resolution.path)")
                return resolution.path
            } catch {
                debugLog("failed to resolve updatebar path: \(error)")
            }
            return "/opt/homebrew/bin/updatebar"
        }

        private static func makeService(cliPath: String) -> any MenuBarServicing {
            let environment = ProcessInfo.processInfo.environment
            if environment["UPDATEBAR_MENUBAR_ADAPTER"] == "cli" {
                debugLog("using CLI subprocess menu bar adapter")
                return UpdateBarCLIClient(executablePath: cliPath)
            }
            debugLog("using direct UpdateBarCore menu bar adapter")
            return CoreMenuBarService(
                githubToken: environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"]
            )
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

    private enum MenuBarStartupError: Error, CustomStringConvertible {
        case missingStatusBarButton

        var description: String {
            switch self {
            case .missingStatusBarButton:
                return "Failed to create menu bar button"
            }
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
