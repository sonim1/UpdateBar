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
    case separator
}

public struct MenuBarMenuItem: Equatable, Sendable {
    public var title: String
    public var action: MenuBarMenuItemAction?
    public var toolTip: String?

    public init(title: String, action: MenuBarMenuItemAction? = nil, toolTip: String? = nil) {
        self.title = title
        self.action = action
        self.toolTip = toolTip
    }
}

public enum MenuBarMenuItemAction: Equatable, Sendable {
    case menu(MenuBarMenuAction)
    case cancelCurrentAction
    case update(id: String)
    case approve(id: String, field: String)
    case revoke(id: String, field: String)
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
        lastActionNotice: String? = nil
    ) -> MenuBarMenuModel {
        var entries: [MenuBarMenuEntry] = []

        if let activeActionTitle {
            appendDisabled("Running: \(activeActionTitle)", to: &entries)
            appendAction(
                "Cancel Current Action",
                action: .cancelCurrentAction,
                to: &entries
            )
            appendSeparator(to: &entries)
        } else if let lastActionNotice {
            appendDisabled(lastActionNotice, to: &entries)
            appendSeparator(to: &entries)
        }

        appendDisabled(state.title, to: &entries)
        if state.needsAttentionCount > 0 {
            appendDisabled("\(state.needsAttentionCount) need attention", to: &entries)
        }
        appendSeparator(to: &entries)
        appendAction(MenuBarMenuAction.checkNow.title, action: .menu(.checkNow), to: &entries)
        appendAction(
            MenuBarMenuAction.updateAllApprovedOutdated.title,
            action: .menu(.updateAllApprovedOutdated),
            to: &entries
        )
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
        for action in MenuBarMenuAction.footer {
            appendAction(action.title, action: .menu(action), to: &entries)
        }

        return MenuBarMenuModel(entries: entries)
    }

    public func makeErrorMenu(errorDescription: String) -> MenuBarMenuModel {
        var entries: [MenuBarMenuEntry] = []
        appendDisabled("UpdateBar Error", to: &entries)
        appendDisabled(errorDescription, to: &entries)
        appendSeparator(to: &entries)
        for action in MenuBarMenuAction.errorRecovery {
            appendAction(action.title, action: .menu(action), to: &entries)
        }
        return MenuBarMenuModel(entries: entries)
    }

    private func appendUpdates(_ items: [StatusItem], to entries: inout [MenuBarMenuEntry]) {
        appendSection("Updates", items: items, to: &entries) { item in
            MenuBarMenuItem(
                title: "\(item.name) \(item.current ?? "?") -> \(item.latest ?? "?")",
                action: .update(id: item.id)
            )
        }
    }

    private func appendApprovals(
        _ items: [StatusItem],
        approvalStatuses: [String: [CommandApprovalStatus]],
        to entries: inout [MenuBarMenuEntry]
    ) {
        guard !items.isEmpty else { return }
        appendDisabled("Needs Approval", to: &entries)
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
                appendDisabled("  \(item.name): no command fields", to: &entries)
                addedItems += 1
                continue
            }

            if addedItems >= Self.maxApprovalItems {
                break
            }

            let plural = approvals.count == 1 ? "" : "s"
            appendDisabled("  \(item.name) (\(approvals.count) command\(plural))", to: &entries)
            addedItems += 1

            let remaining = Self.maxApprovalItems - addedItems
            let showCount = min(approvals.count, min(Self.maxApprovalRowsPerItem, remaining))
            for approval in approvals.prefix(showCount) {
                let verb = approval.approved ? "Revoke" : "Approve"
                let command = collapseWhitespace(in: approval.command)
                let cwd = approval.cwd.map { " [cwd: \($0)]" } ?? ""
                let action: MenuBarMenuItemAction =
                    approval.approved
                    ? .revoke(id: item.id, field: approval.field)
                    : .approve(id: item.id, field: approval.field)
                guard showCount > 0 else { break }
                let label = "      \(verb) \(approval.field): \(command)\(cwd)"
                entries.append(
                    .item(
                        MenuBarMenuItem(
                            title: label,
                            action: action,
                            toolTip: "\(approval.field): \(approval.command)\(cwd)"
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
        appendSection("Errors", items: items, to: &entries) { item in
            MenuBarMenuItem(title: "\(item.name): \(item.error ?? "error")")
        }
    }

    private func appendInstalled(_ items: [StatusItem], to entries: inout [MenuBarMenuEntry]) {
        appendSection("Installed", items: items, to: &entries) { item in
            MenuBarMenuItem(title: "\(item.name) \(item.current ?? "")")
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

    private func appendDisabled(_ title: String, to entries: inout [MenuBarMenuEntry]) {
        entries.append(.item(MenuBarMenuItem(title: title)))
    }

    private func appendAction(
        _ title: String,
        action: MenuBarMenuItemAction,
        to entries: inout [MenuBarMenuEntry]
    ) {
        entries.append(.item(MenuBarMenuItem(title: title, action: action)))
    }

    private func appendSeparator(to entries: inout [MenuBarMenuEntry]) {
        guard !entries.isEmpty, entries.last != .separator else { return }
        entries.append(.separator)
    }

    private func collapseWhitespace(in value: String) -> String {
        value.split { $0.isWhitespace }.joined(separator: " ")
    }
}
