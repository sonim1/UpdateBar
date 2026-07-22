import Foundation
import UpdateBarCore

public struct MenuBarMenuModel: Equatable, Sendable {
    public var entries: [MenuBarMenuEntry]

    public init(entries: [MenuBarMenuEntry]) {
        self.entries = entries
    }
}

public enum MenuBarMenuEntry: Equatable, Sendable {
    case item(MenuBarMenuItem)
    case submenu(MenuBarSubmenu)
    case separator
}

public struct MenuBarSubmenu: Equatable, Sendable {
    public var title: String
    public var items: [MenuBarMenuItem]
    public var systemSymbolName: String?

    public init(
        title: String,
        items: [MenuBarMenuItem],
        systemSymbolName: String? = nil
    ) {
        self.title = title
        self.items = items
        self.systemSymbolName = systemSymbolName
    }
}

public struct MenuBarMenuItem: Equatable, Sendable {
    public var title: String
    public var action: MenuBarMenuItemAction?
    public var toolTip: String?
    public var confirmation: MenuBarActionConfirmation?
    public var isChecked: Bool
    public var systemSymbolName: String?
    /// Bundle identifier of an app whose icon should decorate the item.
    public var iconAppBundleID: String?

    public init(
        title: String,
        action: MenuBarMenuItemAction? = nil,
        toolTip: String? = nil,
        confirmation: MenuBarActionConfirmation? = nil,
        isChecked: Bool = false,
        systemSymbolName: String? = nil,
        iconAppBundleID: String? = nil
    ) {
        self.title = title
        self.action = action
        self.toolTip = toolTip
        self.confirmation = confirmation
        self.isChecked = isChecked
        self.systemSymbolName = systemSymbolName
        self.iconAppBundleID = iconAppBundleID
    }
}

public enum MenuBarMenuItemAction: Equatable, Sendable {
    case menu(MenuBarMenuAction)
    case cancelCurrentAction
    case update(id: String)
    case approve(id: String, field: String)
    case revoke(id: String, field: String)
    case openTUIInTerminal(bundleID: String)
}

public struct MenuBarMenuModelBuilder: Sendable {
    public init() {}

    private static let maxSectionItems = 6
    private static let maxApprovalItems = 8

    public func makeLoadingMenu() -> MenuBarMenuModel {
        var entries: [MenuBarMenuEntry] = []
        appendDisabled("Checking for updates...", to: &entries)
        appendSeparator(to: &entries)
        for action in [MenuBarMenuAction.overview, .quit] {
            appendAction(action.title, action: .menu(action), to: &entries)
        }
        return MenuBarMenuModel(entries: entries)
    }

    public func makeMenu(
        state: MenuBarState,
        approvalStatuses: [String: [CommandApprovalStatus]],
        activeActionTitle: String? = nil,
        lastActionNotice: String? = nil,
        installedTerminals: [TUITerminal] = [],
        selectedTerminalID: String? = nil
    ) -> MenuBarMenuModel {
        var entries: [MenuBarMenuEntry] = []

        if let activeActionTitle {
            appendDisabled("\(SecretRedactor.redact(activeActionTitle))...", to: &entries)
            appendAction(
                "Cancel Current Action",
                action: .cancelCurrentAction,
                to: &entries
            )
            appendSeparator(to: &entries)
            appendFooterActions(
                installedTerminals: installedTerminals,
                selectedTerminalID: selectedTerminalID,
                to: &entries
            )
            return MenuBarMenuModel(entries: entries)
        }

        if let lastActionNotice {
            appendDisabled(SecretRedactor.redact(lastActionNotice), to: &entries)
            appendSeparator(to: &entries)
        }

        appendDisabled(state.title, to: &entries)
        if let needsAttentionSummary = state.needsAttentionSummary {
            appendDisabled(needsAttentionSummary, to: &entries)
        }
        appendSeparator(to: &entries)
        appendAction(MenuBarMenuAction.checkNow.title, action: .menu(.checkNow), to: &entries)
        appendAction(
            MenuBarMenuAction.refreshStatus.title, action: .menu(.refreshStatus), to: &entries)
        let updateAllAction = MenuBarMenuAction.updateAllApprovedOutdated
        if state.outdatedItems.isEmpty {
            appendDisabled(updateAllAction.title, toolTip: "No updates available.", to: &entries)
        } else {
            appendAction(
                updateAllAction.title,
                action: .menu(updateAllAction),
                toolTip: "Updates all \(state.outdatedItems.count) approved outdated items.",
                to: &entries
            )
        }
        appendSeparator(to: &entries)

        appendUpdates(state.outdatedItems, to: &entries)
        appendApprovals(
            state.approvalItems,
            approvalStatuses: approvalStatuses,
            to: &entries
        )
        appendErrors(state.errorItems, to: &entries)
        appendInstalled(state.okItems, to: &entries)

        appendSeparator(to: &entries)
        appendFooterActions(
            installedTerminals: installedTerminals,
            selectedTerminalID: selectedTerminalID,
            to: &entries
        )

        return MenuBarMenuModel(entries: entries)
    }

    private func appendFooterActions(
        installedTerminals: [TUITerminal],
        selectedTerminalID: String?,
        to entries: inout [MenuBarMenuEntry]
    ) {
        for action in MenuBarMenuAction.footer {
            if action == .openTUI, installedTerminals.count > 1 {
                appendOpenTUISubmenu(
                    installedTerminals,
                    selectedTerminalID: selectedTerminalID,
                    to: &entries
                )
            } else {
                appendAction(action.title, action: .menu(action), to: &entries)
            }
        }
    }

    private func appendOpenTUISubmenu(
        _ terminals: [TUITerminal],
        selectedTerminalID: String?,
        to entries: inout [MenuBarMenuEntry]
    ) {
        let lastUsedID =
            terminals.contains { $0.id == selectedTerminalID }
            ? selectedTerminalID : TUITerminal.fallback.id
        let items = terminals.map { terminal in
            MenuBarMenuItem(
                title: terminal.name,
                action: .openTUIInTerminal(bundleID: terminal.id),
                isChecked: terminal.id == lastUsedID,
                iconAppBundleID: terminal.id
            )
        }
        entries.append(
            .submenu(MenuBarSubmenu(title: MenuBarMenuAction.openTUI.title, items: items))
        )
    }

    public func makeErrorMenu(errorDescription: String) -> MenuBarMenuModel {
        var entries: [MenuBarMenuEntry] = []
        appendDisabled("UpdateBar Error", to: &entries)
        appendDisabled(SecretRedactor.redact(errorDescription), to: &entries)
        appendSeparator(to: &entries)
        for action in MenuBarMenuAction.errorRecovery {
            appendAction(action.title, action: .menu(action), to: &entries)
        }
        return MenuBarMenuModel(entries: entries)
    }

    private func appendUpdates(_ items: [StatusItem], to entries: inout [MenuBarMenuEntry]) {
        appendSection("Updates (\(items.count))", items: items, to: &entries) { item in
            let name = SecretRedactor.redact(item.name)
            let current = item.current.map(SecretRedactor.redact) ?? "?"
            let latest = item.latest.map(SecretRedactor.redact) ?? "?"
            return MenuBarMenuItem(
                title: "\(name) \(current) -> \(latest)",
                action: .update(id: item.id),
                toolTip: "Updates \(SecretRedactor.redact(item.id)) immediately."
            )
        }
    }

    private func appendApprovals(
        _ items: [StatusItem],
        approvalStatuses: [String: [CommandApprovalStatus]],
        to entries: inout [MenuBarMenuEntry]
    ) {
        guard !items.isEmpty else { return }
        appendDisabled("Command Approval Required (\(items.count))", to: &entries)
        for item in items.prefix(Self.maxApprovalItems) {
            let approvals = approvalStatuses[item.id] ?? []
            if approvals.isEmpty {
                appendDisabled(
                    SecretRedactor.redact(item.name),
                    systemSymbolName: "questionmark.circle",
                    to: &entries
                )
                continue
            }

            let approvedStates = Set(approvals.map(\.approved))
            let systemSymbolName =
                approvedStates.count == 2
                ? "circle.lefthalf.filled" : "exclamationmark.circle"
            entries.append(
                .submenu(
                    MenuBarSubmenu(
                        title: SecretRedactor.redact(item.name),
                        items: approvals.map { approvalMenuItem(for: item, approval: $0) },
                        systemSymbolName: systemSymbolName
                    )
                )
            )
        }
        let overflow = items.count - Self.maxApprovalItems
        if overflow > 0 {
            appendDisabled("and \(overflow) more", to: &entries)
        }
        appendSeparator(to: &entries)
    }

    private func approvalMenuItem(
        for item: StatusItem,
        approval: CommandApprovalStatus
    ) -> MenuBarMenuItem {
        let verb = approval.approved ? "Revoke" : "Approve"
        let action: MenuBarMenuItemAction =
            approval.approved
            ? .revoke(id: item.id, field: approval.field)
            : .approve(id: item.id, field: approval.field)
        let confirmation = MenuBarActionConfirmation.commandApproval(
            for: item,
            status: approval
        )
        return MenuBarMenuItem(
            title: "\(verb) \(approvalFieldTitle(approval.field))",
            action: action,
            toolTip: confirmation.toolTip,
            confirmation: confirmation,
            systemSymbolName: approval.approved ? "checkmark.circle" : "circle"
        )
    }

    private func approvalFieldTitle(_ field: String) -> String {
        switch field {
        case "check.cmd":
            return "Check"
        case "latest.cmd":
            return "Latest"
        case "update.cmd":
            return "Update"
        default:
            return SecretRedactor.redact(field)
        }
    }

    private func appendErrors(_ items: [StatusItem], to entries: inout [MenuBarMenuEntry]) {
        appendSection("Errors (\(items.count))", items: items, to: &entries) { item in
            let name = SecretRedactor.redact(item.name)
            let error = SecretRedactor.redact(item.error ?? "error")
            return MenuBarMenuItem(title: "\(name): \(error)")
        }
    }

    private func appendInstalled(_ items: [StatusItem], to entries: inout [MenuBarMenuEntry]) {
        appendSection("Installed (\(items.count))", items: items, to: &entries) { item in
            let name = SecretRedactor.redact(item.name)
            let current = item.current.map { " \(SecretRedactor.redact($0))" } ?? ""
            return MenuBarMenuItem(title: "\(name)\(current)")
        }
    }

    private func appendSection(
        _ title: String,
        items: [StatusItem],
        to entries: inout [MenuBarMenuEntry],
        makeItem: (StatusItem) -> MenuBarMenuItem
    ) {
        guard !items.isEmpty else { return }
        appendDisabled(title, to: &entries)
        for item in items.prefix(Self.maxSectionItems) {
            entries.append(.item(makeItem(item)))
        }
        let overflow = items.count - Self.maxSectionItems
        if overflow > 0 {
            appendDisabled("and \(overflow) more", to: &entries)
        }
        appendSeparator(to: &entries)
    }

    private func appendDisabled(
        _ title: String,
        toolTip: String? = nil,
        systemSymbolName: String? = nil,
        to entries: inout [MenuBarMenuEntry]
    ) {
        entries.append(
            .item(
                MenuBarMenuItem(
                    title: title,
                    toolTip: toolTip,
                    systemSymbolName: systemSymbolName
                )))
    }

    private func appendAction(
        _ title: String,
        action: MenuBarMenuItemAction,
        toolTip: String? = nil,
        confirmation: MenuBarActionConfirmation? = nil,
        to entries: inout [MenuBarMenuEntry]
    ) {
        entries.append(
            .item(
                MenuBarMenuItem(
                    title: title,
                    action: action,
                    toolTip: toolTip,
                    confirmation: confirmation
                )))
    }

    private func appendSeparator(to entries: inout [MenuBarMenuEntry]) {
        guard !entries.isEmpty, entries.last != .separator else { return }
        entries.append(.separator)
    }
}
