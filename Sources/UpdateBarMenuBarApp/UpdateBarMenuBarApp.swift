#if os(macOS)
    import AppKit
    import Foundation
    import UpdateBarCore
    import UpdateBarMenuBar

    @main
    @MainActor
    final class UpdateBarMenuBarApp: NSObject, NSApplicationDelegate {
        private static var bootstrapDelegate: UpdateBarMenuBarApp?
        private var statusItem: NSStatusItem?
        private var service: (any MenuBarServicing)?
        private var cliPath = ""
        private let formatter = MenuBarStatusFormatter()
        private let menuBuilder = MenuBarMenuModelBuilder()
        private let actionCoordinator = MenuBarActionCoordinator()
        private var scanPanelController: ScanPanelController?
        private var configPanelController: ConfigPanelController?
        private var manageItemsPanelController: ManageItemsPanelController?
        private var latestState = MenuBarState(
            title: "Checking...",
            badgeValue: "...",
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
            let useCLIAdapter = Self.shouldUseCLIAdapter()
            if useCLIAdapter {
                let resolvedPath = Self.resolveCLIPath()
                if !resolvedPath.isEmpty {
                    cliPath = resolvedPath
                }
            }
            service = Self.makeService(cliPath: useCLIAdapter ? cliPath : nil)
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem = item
            item.autosaveName = "UpdateBarStatusItem"
            item.isVisible = true
            guard let statusButton = item.button else {
                showError(MenuBarStartupError.missingStatusBarButton)
                return
            }

            statusButton.title = "..."
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

        @objc private func updateAllApproved(_ sender: NSMenuItem) {
            let fallback = MenuBarActionConfirmation.updateAllApprovedOutdated(
                itemNames: latestState.outdatedItems.map(\.name)
            )
            guard confirm((sender.representedObject as? MenuBarActionConfirmation) ?? fallback)
            else {
                return
            }
            runAction("Run Updates") { [service] token in
                try service?.updateAllApproved(cancellationToken: token)
            }
        }

        @objc private func updateSelected(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ItemAction else { return }
            let id = action.id
            guard confirm(action.confirmation ?? MenuBarActionConfirmation.updateItem(id: id))
            else {
                return
            }
            runAction("Update \(id)") { [service] token in
                try service?.update(id: id, cancellationToken: token)
            }
        }

        @objc private func approveField(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ApprovalAction else { return }
            let id = action.id
            let field = action.field
            let fallback = MenuBarActionConfirmation.commandApproval(
                id: id,
                field: field,
                approving: true
            )
            guard confirm(action.confirmation ?? fallback) else { return }
            runAction("Approve \(id) \(field)") { [service] token in
                try service?.approve(id: id, field: field, cancellationToken: token)
            }
        }

        @objc private func revokeField(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ApprovalAction else { return }
            let id = action.id
            let field = action.field
            let fallback = MenuBarActionConfirmation.commandApproval(
                id: id,
                field: field,
                approving: false
            )
            guard confirm(action.confirmation ?? fallback) else { return }
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
            launchTUI(in: selectedTerminal())
        }

        @objc private func scanAndAdd() {
            guard let service else {
                showError(MenuBarStartupError.serviceUnavailable)
                return
            }
            if scanPanelController == nil {
                scanPanelController = ScanPanelController(
                    service: service,
                    onRegistered: { [weak self] in
                        self?.refreshStatus(refresh: false)
                    }
                )
            }
            scanPanelController?.showScanWindow()
        }

        @objc private func manageItems() {
            guard let service else {
                showError(MenuBarStartupError.serviceUnavailable)
                return
            }
            if manageItemsPanelController == nil {
                manageItemsPanelController = ManageItemsPanelController(
                    service: service,
                    onChanged: { [weak self] in
                        self?.refreshStatus(refresh: false)
                    }
                )
            }
            manageItemsPanelController?.showWindowAndReload()
        }

        @objc private func openTUIInTerminal(_ sender: NSMenuItem) {
            guard let bundleID = sender.representedObject as? String,
                let terminal = installedTerminals().first(where: { $0.id == bundleID })
            else { return }
            UserDefaults.standard.set(bundleID, forKey: Self.tuiTerminalDefaultsKey)
            launchTUI(in: terminal)
        }

        private func launchTUI(in terminal: TUITerminal) {
            let resolvedCLIPath = cliPath.isEmpty ? Self.resolveCLIPath() : cliPath
            guard !resolvedCLIPath.isEmpty else {
                showError(MenuBarStartupError.cliResolverFailed)
                return
            }
            do {
                let commandFileURL = Self.tuiCommandFileURL
                let command = OpenTUICommand(
                    cliPath: resolvedCLIPath,
                    commandFileURL: commandFileURL,
                    terminal: terminal
                )
                try FileManager.default.createDirectory(
                    at: commandFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try command.commandFileContents.write(
                    to: commandFileURL,
                    atomically: true,
                    encoding: .utf8
                )
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: commandFileURL.path
                )
                if let auxiliaryFile = command.auxiliaryFile {
                    try FileManager.default.createDirectory(
                        at: auxiliaryFile.url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try auxiliaryFile.contents.write(
                        to: auxiliaryFile.url,
                        atomically: true,
                        encoding: .utf8
                    )
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command.executablePath)
                process.arguments = command.arguments
                try process.run()
            } catch {
                showError(error)
            }
        }

        private static let tuiTerminalDefaultsKey = "TUITerminalBundleID"

        private static var tuiCommandFileURL: URL {
            let base =
                FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return
                base
                .appendingPathComponent("UpdateBar", isDirectory: true)
                .appendingPathComponent("open-tui.command", isDirectory: false)
        }

        private func installedTerminals() -> [TUITerminal] {
            TUITerminal.known.filter {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil
            }
        }

        private func selectedTerminal() -> TUITerminal {
            let installed = installedTerminals()
            if let id = UserDefaults.standard.string(forKey: Self.tuiTerminalDefaultsKey),
                let terminal = installed.first(where: { $0.id == id })
            {
                return terminal
            }
            return installed.first { $0.id == TUITerminal.fallback.id }
                ?? installed.first
                ?? TUITerminal.fallback
        }

        @objc private func openConfig() {
            guard let service else {
                showError(MenuBarStartupError.serviceUnavailable)
                return
            }
            if configPanelController == nil {
                configPanelController = ConfigPanelController(
                    service: service,
                    onSaved: { [weak self] in
                        self?.refreshStatus(refresh: false)
                    }
                )
            }
            configPanelController?.showWindowAndLoad()
        }

        @objc private func viewLogs() {
            let logURL = Self.logFileURL
            let targetURL =
                FileManager.default.fileExists(atPath: logURL.path)
                ? logURL : AppPaths().homeDirectory
            openInFinder(
                targetURL, failureMessage: MenuBarStartupError.viewLogFailed(path: targetURL.path))
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
            guard let statusItem else {
                Self.debugLog("cannot rebuild menu before status item exists")
                return
            }
            let activeAction = actionCoordinator.activeAction
            let lastActionNotice = actionCoordinator.lastActionNotice
            if let activeAction {
                setTitle("...", accessibilityLabel: "UpdateBar running \(activeAction.title)")
            } else {
                setTitle(
                    latestState.badgeValue ?? "✓",
                    accessibilityLabel: accessibilityLabel(for: latestState)
                )
            }
            let model = menuBuilder.makeMenu(
                state: latestState,
                approvalStatuses: approvalStatuses,
                activeActionTitle: activeAction?.title,
                lastActionNotice: activeAction == nil ? lastActionNotice : nil,
                installedTerminals: installedTerminals(),
                selectedTerminalID: selectedTerminal().id
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
                case .submenu(let submenu):
                    let parent = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
                    let child = NSMenu(title: submenu.title)
                    for item in submenu.items {
                        child.addItem(menuItem(from: item))
                    }
                    parent.submenu = child
                    menu.addItem(parent)
                }
            }
            return menu
        }

        private func menuItem(from item: MenuBarMenuItem) -> NSMenuItem {
            guard let action = item.action else {
                return disabledItem(item.title, toolTip: item.toolTip)
            }
            let menuItem = actionItem(item.title, action: selector(for: action))
            menuItem.toolTip = item.toolTip
            menuItem.state = item.isChecked ? .on : .off
            if let bundleID = item.iconAppBundleID,
                let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 16, height: 16)
                menuItem.image = icon
            }
            switch action {
            case .menu, .cancelCurrentAction:
                if action == .menu(.updateAllApprovedOutdated) {
                    menuItem.representedObject = item.confirmation
                }
            case .update(let id):
                menuItem.representedObject = ItemAction(id: id, confirmation: item.confirmation)
            case .approve(let id, let field), .revoke(let id, let field):
                menuItem.representedObject = ApprovalAction(
                    id: id,
                    field: field,
                    confirmation: item.confirmation
                )
            case .openTUIInTerminal(let bundleID):
                menuItem.representedObject = bundleID
            }
            return menuItem
        }

        private func showError(_ error: Error) {
            let errorDescription = SecretRedactor.redact(String(describing: error))
            Self.debugLog("showing error: \(errorDescription)")
            setTitle("!", accessibilityLabel: "UpdateBar error")
            guard let statusItem else {
                return
            }
            let model = menuBuilder.makeErrorMenu(
                errorDescription: errorDescription
            )
            statusItem.menu = makeMenu(from: model)
        }

        private func setTitle(_ title: String, accessibilityLabel: String? = nil) {
            statusItem?.button?.title = title
            statusItem?.button?.setAccessibilityLabel(accessibilityLabel ?? "UpdateBar \(title)")
        }

        private func accessibilityLabel(for state: MenuBarState) -> String {
            if state.needsAttentionCount > 0 {
                return "UpdateBar \(state.title), \(state.needsAttentionCount) need attention"
            }
            return "UpdateBar \(state.title)"
        }

        private static func debugLog(_ message: String) {
            let redactedMessage = SecretRedactor.redact(message)
            FileHandle.standardError.write(Data(("UpdateBarMenuBar: \(redactedMessage)\n").utf8))
            appendLog(redactedMessage)
        }

        private func openInFinder(_ targetURL: URL, failureMessage: Error) {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            if NSWorkspace.shared.open(targetURL) {
                return
            }
            if NSWorkspace.shared.open(targetURL.deletingLastPathComponent()) {
                return
            }
            showError(failureMessage)
        }

        private func confirm(_ confirmation: MenuBarActionConfirmation?) -> Bool {
            guard let confirmation else { return true }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = confirmation.title
            alert.informativeText = confirmation.message
            alert.addButton(withTitle: confirmation.confirmButton)
            alert.addButton(withTitle: confirmation.cancelButton)
            return alert.runModal() == .alertFirstButtonReturn
        }

        private static var logDirectory: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("UpdateBar", isDirectory: true)
        }

        private static var logFileURL: URL {
            logDirectory.appendingPathComponent("updatebar-menubar.log", isDirectory: false)
        }

        private static let maxLogFileBytes: Int = 256 * 1024

        private static let dateFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        private static func appendLog(_ message: String) {
            do {
                try FileManager.default.createDirectory(
                    at: logDirectory,
                    withIntermediateDirectories: true
                )

                let line = "\(dateFormatter.string(from: Date())) UpdateBarMenuBar: \(message)\n"
                let data = Data(line.utf8)

                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    let existing = try Data(contentsOf: logFileURL)
                    let concatenated = existing + data
                    if concatenated.count <= maxLogFileBytes {
                        try concatenated.write(to: logFileURL, options: .atomic)
                        return
                    }
                    let trimmed = concatenated.suffix(maxLogFileBytes)
                    try trimmed.write(to: logFileURL, options: .atomic)
                    return
                }
                try data.write(to: logFileURL)
            } catch {
                // Logging should not block or fail app startup.
            }
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
            case .openTUIInTerminal:
                return #selector(openTUIInTerminal(_:))
            }
        }

        private func selector(for action: MenuBarMenuAction) -> Selector {
            switch action {
            case .refreshStatus:
                return #selector(refreshFromMenu)
            case .checkNow:
                return #selector(checkNow)
            case .updateAllApprovedOutdated:
                return #selector(updateAllApproved(_:))
            case .openTUI:
                return #selector(openTUI)
            case .manageItems:
                return #selector(manageItems)
            case .scanAndAdd:
                return #selector(scanAndAdd)
            case .openConfig:
                return #selector(openConfig)
            case .viewLogs:
                return #selector(viewLogs)
            case .quit:
                return #selector(quit)
            }
        }

        private func disabledItem(_ title: String, toolTip: String? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = toolTip ?? title
            return item
        }

        private static func resolveCLIPath() -> String {
            do {
                let resolution = try UpdateBarBinaryResolver().resolve(
                    bundledDirectory: Bundle.main.resourceURL
                )
                let redactedPath = SecretRedactor.redact(resolution.path)
                debugLog("using \(resolution.source.rawValue) updatebar: \(redactedPath)")
                return resolution.path
            } catch {
                debugLog("failed to resolve updatebar path: \(error)")
                return ""
            }
        }

        private static func shouldUseCLIAdapter() -> Bool {
            ProcessInfo.processInfo.environment["UPDATEBAR_MENUBAR_ADAPTER"] == "cli"
        }

        private static func makeService(cliPath: String?) -> any MenuBarServicing {
            if shouldUseCLIAdapter(), let cliPath, !cliPath.isEmpty {
                debugLog("using CLI subprocess menu bar adapter")
                return UpdateBarCLIClient(executablePath: cliPath)
            }
            if shouldUseCLIAdapter() {
                debugLog("CLI adapter requested but no executable was resolved; using core adapter")
            }
            let environment = ProcessInfo.processInfo.environment
            debugLog("using direct UpdateBarCore menu bar adapter")
            return CoreMenuBarService(
                githubToken: environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"]
            )
        }
    }

    private final class ItemAction: NSObject {
        let id: String
        let confirmation: MenuBarActionConfirmation?

        init(id: String, confirmation: MenuBarActionConfirmation?) {
            self.id = id
            self.confirmation = confirmation
        }
    }

    private final class ApprovalAction: NSObject {
        let id: String
        let field: String
        let confirmation: MenuBarActionConfirmation?

        init(id: String, field: String, confirmation: MenuBarActionConfirmation?) {
            self.id = id
            self.field = field
            self.confirmation = confirmation
        }
    }

    private enum MenuBarStartupError: Error, CustomStringConvertible {
        case missingStatusBarButton
        case viewLogFailed(path: String)
        case cliResolverFailed
        case serviceUnavailable

        var description: String {
            switch self {
            case .missingStatusBarButton:
                return "Failed to create menu bar button"
            case .viewLogFailed(let path):
                return "Failed to open log target at \(path)"
            case .cliResolverFailed:
                return "Unable to resolve updatebar executable for Open TUI"
            case .serviceUnavailable:
                return "UpdateBar service is unavailable"
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
