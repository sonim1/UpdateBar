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

    public init(title: String, items: [MenuBarMenuItem]) {
        self.title = title
        self.items = items
    }
}

public struct MenuBarMenuItem: Equatable, Sendable {
    public var title: String
    public var action: MenuBarMenuItemAction?
    public var toolTip: String?
    public var confirmation: MenuBarActionConfirmation?
    public var isChecked: Bool
    /// Bundle identifier of an app whose icon should decorate the item.
    public var iconAppBundleID: String?

    public init(
        title: String,
        action: MenuBarMenuItemAction? = nil,
        toolTip: String? = nil,
        confirmation: MenuBarActionConfirmation? = nil,
        isChecked: Bool = false,
        iconAppBundleID: String? = nil
    ) {
        self.title = title
        self.action = action
        self.toolTip = toolTip
        self.confirmation = confirmation
        self.isChecked = isChecked
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
    private static let maxApprovalRowsPerItem = 2

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
            appendDisabled("Running: \(SecretRedactor.redact(activeActionTitle))", to: &entries)
            appendAction(
                "Cancel Current Action",
                action: .cancelCurrentAction,
                to: &entries
            )
            appendSeparator(to: &entries)
        } else if let lastActionNotice {
            appendDisabled(SecretRedactor.redact(lastActionNotice), to: &entries)
            appendSeparator(to: &entries)
        }

        appendDisabled(state.title, to: &entries)
        if state.needsAttentionCount > 0 {
            appendDisabled("\(state.needsAttentionCount) need attention", to: &entries)
        }
        appendSeparator(to: &entries)
        appendAction(MenuBarMenuAction.checkNow.title, action: .menu(.checkNow), to: &entries)
        appendAction(
            MenuBarMenuAction.refreshStatus.title, action: .menu(.refreshStatus), to: &entries)
        let updateAllAction = MenuBarMenuAction.updateAllApprovedOutdated
        if state.outdatedItems.isEmpty {
            appendDisabled(updateAllAction.title, toolTip: "No updates available.", to: &entries)
        } else {
            let confirmation = MenuBarActionConfirmation.updateAllApprovedOutdated(
                itemNames: state.outdatedItems.map { SecretRedactor.redact($0.name) }
            )
            appendAction(
                updateAllAction.title,
                action: .menu(updateAllAction),
                toolTip: confirmation.toolTip,
                confirmation: confirmation,
                to: &entries
            )
        }
        appendSeparator(to: &entries)

        appendUpdates(
            state.outdatedItems,
            approvalStatuses: approvalStatuses,
            to: &entries
        )
        appendApprovals(
            state.approvalItems,
            approvalStatuses: approvalStatuses,
            to: &entries
        )
        appendErrors(state.errorItems, to: &entries)
        appendInstalled(state.okItems, to: &entries)

        appendSeparator(to: &entries)
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

        return MenuBarMenuModel(entries: entries)
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

    private func appendUpdates(
        _ items: [StatusItem],
        approvalStatuses: [String: [CommandApprovalStatus]],
        to entries: inout [MenuBarMenuEntry]
    ) {
        appendSection("Updates (\(items.count))", items: items, to: &entries) { item in
            let updateCommand = approvalStatuses[item.id]?.first { $0.field == "update.cmd" }
            let name = SecretRedactor.redact(item.name)
            let current = item.current.map(SecretRedactor.redact) ?? "?"
            let latest = item.latest.map(SecretRedactor.redact) ?? "?"
            let confirmation = MenuBarActionConfirmation.updateItem(
                id: SecretRedactor.redact(item.id),
                command: updateCommand.map { SecretRedactor.redact($0.command) },
                cwd: updateCommand?.cwd.map(SecretRedactor.redact)
            )
            return MenuBarMenuItem(
                title: "\(name) \(current) -> \(latest)",
                action: .update(id: item.id),
                toolTip: confirmation.toolTip,
                confirmation: confirmation
            )
        }
    }

    private func appendApprovals(
        _ items: [StatusItem],
        approvalStatuses: [String: [CommandApprovalStatus]],
        to entries: inout [MenuBarMenuEntry]
    ) {
        guard !items.isEmpty else { return }
        appendDisabled("Needs Approval (\(items.count))", to: &entries)
        var addedItems = 0
        let totalApprovalRows = items.reduce(0) { total, item in
            let approvals = approvalStatuses[item.id] ?? []
            let header = 1
            if approvals.isEmpty {
                return total + header
            }
            let shown = min(approvals.count, Self.maxApprovalRowsPerItem)
            let overflow = approvals.count > shown ? 1 : 0
            return total + header + shown + overflow
        }
        for item in items {
            let approvals = approvalStatuses[item.id] ?? []
            if approvals.isEmpty {
                if addedItems >= Self.maxApprovalItems {
                    break
                }
                appendDisabled(
                    "  \(SecretRedactor.redact(item.name)): no command fields", to: &entries)
                addedItems += 1
                continue
            }

            if addedItems >= Self.maxApprovalItems {
                break
            }

            let plural = approvals.count == 1 ? "" : "s"
            appendDisabled(
                "  \(SecretRedactor.redact(item.name)) (\(approvals.count) command\(plural))",
                to: &entries
            )
            addedItems += 1

            let remaining = Self.maxApprovalItems - addedItems
            let showCount = min(approvals.count, min(Self.maxApprovalRowsPerItem, remaining))
            for approval in approvals.prefix(showCount) {
                let verb = approval.approved ? "Revoke" : "Approve"
                let redactedCommand = SecretRedactor.redact(approval.command)
                let redactedCwd = approval.cwd.map(SecretRedactor.redact)
                let command = collapseWhitespace(in: redactedCommand)
                let cwd = redactedCwd.map { " [cwd: \($0)]" } ?? ""
                let action: MenuBarMenuItemAction =
                    approval.approved
                    ? .revoke(id: item.id, field: approval.field)
                    : .approve(id: item.id, field: approval.field)
                let confirmation = MenuBarActionConfirmation.commandApproval(
                    id: SecretRedactor.redact(item.id),
                    field: approval.field,
                    approving: !approval.approved,
                    command: redactedCommand,
                    cwd: redactedCwd
                )
                guard showCount > 0 else { break }
                let label = "      \(verb) \(approval.field): \(command)\(cwd)"
                entries.append(
                    .item(
                        MenuBarMenuItem(
                            title: label,
                            action: action,
                            toolTip:
                                "\(confirmation.toolTip)\n\(approval.field): \(redactedCommand)\(cwd)",
                            confirmation: confirmation
                        )))
                addedItems += 1
                if addedItems >= Self.maxApprovalItems {
                    break
                }
            }

            let hidden = approvals.count - showCount
            if hidden > 0, addedItems < Self.maxApprovalItems {
                appendDisabled("    + and \(hidden) more", to: &entries)
                addedItems += 1
            }
            if addedItems >= Self.maxApprovalItems {
                break
            }
        }
        if addedItems < totalApprovalRows {
            let overflow = totalApprovalRows - addedItems
            if overflow > 0 {
                appendDisabled("and \(overflow) more actions", to: &entries)
            }
        }
        appendSeparator(to: &entries)
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
        to entries: inout [MenuBarMenuEntry]
    ) {
        entries.append(.item(MenuBarMenuItem(title: title, toolTip: toolTip)))
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

    private func collapseWhitespace(in value: String) -> String {
        value.split { $0.isWhitespace }.joined(separator: " ")
    }
}
