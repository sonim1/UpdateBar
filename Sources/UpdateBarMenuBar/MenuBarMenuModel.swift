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
    case updateHistory(MenuBarUpdateHistory)
    case separator
}

public struct MenuBarUpdateHistory: Equatable, Sendable {
    public var buckets: [DashboardDayCount]

    public init(buckets: [DashboardDayCount]) {
        self.buckets = buckets
    }

    public var totalUpdates: Int {
        buckets.reduce(0) { $0 + $1.count }
    }

    public static func load(
        snapshot: StatusSnapshot,
        loadEvents: () throws -> [HistoryEvent],
        dashboardModel: DashboardModel,
        now: Date
    ) -> Self {
        let events = (try? loadEvents()) ?? []
        return Self(
            buckets: dashboardModel.summary(
                snapshot: snapshot,
                events: events,
                now: now
            ).updatesPerDay
        )
    }

    public static let empty = MenuBarUpdateHistory(buckets: [])
}

public struct MenuBarSubmenu: Equatable, Sendable {
    public var id: String
    public var title: String
    public var items: [MenuBarMenuItem]
    public var systemSymbolName: String?

    public init(
        title: String,
        items: [MenuBarMenuItem],
        systemSymbolName: String? = nil,
        id: String? = nil
    ) {
        self.id = id ?? title
        self.title = title
        self.items = items
        self.systemSymbolName = systemSymbolName
    }
}

public struct MenuBarMenuItem: Equatable, Sendable {
    public var id: String
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
        iconAppBundleID: String? = nil,
        id: String? = nil
    ) {
        self.id = id ?? title
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
    case stopCurrentAction
    case update(id: String)
    case approve(id: String, reviewed: CommandApprovalStatus)
    case revoke(id: String, reviewed: CommandApprovalStatus)
    case openTUIInTerminal(bundleID: String)
}

public struct MenuBarMenuModelBuilder: Sendable {
    public init() {}

    private static let maxSectionItems = 6
    private static let maxApprovalItems = 8

    public func makeLoadingMenu() -> MenuBarMenuModel {
        var entries: [MenuBarMenuEntry] = []
        appendDisabled(
            "Checking for updates...", systemSymbolName: "arrow.triangle.2.circlepath",
            id: "summary", to: &entries)
        appendSeparator(to: &entries)
        for action in [MenuBarMenuAction.overview, .quit] {
            appendAction(action.title, action: .menu(action), to: &entries)
        }
        return MenuBarMenuModel(entries: entries)
    }

    public func makeMenu(
        state: MenuBarState,
        approvalStatuses: [String: [CommandApprovalStatus]],
        updateHistory: MenuBarUpdateHistory,
        activeActionTitle: String? = nil,
        activeItemProgress: MenuBarItemProgress? = nil,
        activeUpdateItems: [StatusItem]? = nil,
        isStopRequested: Bool = false,
        supportsStopAfterCurrent: Bool = true,
        lastActionNotice: String? = nil
    ) -> MenuBarMenuModel {
        var entries: [MenuBarMenuEntry] = []
        let progress =
            activeActionTitle == nil ? nil : (activeItemProgress ?? MenuBarItemProgress())

        if let activeActionTitle {
            let counted =
                progress.flatMap {
                    $0.totalCount > 0 ? " (\($0.completedCount)/\($0.totalCount))" : nil
                }
                ?? ""
            appendDisabled(
                "\(SecretRedactor.redact(activeActionTitle))…\(counted)",
                systemSymbolName: "arrow.triangle.2.circlepath",
                id: "summary",
                to: &entries
            )
        } else {
            appendDisabled(
                state.title,
                systemSymbolName: state.needsAttentionCount > 0
                    ? "exclamationmark.circle"
                    : (state.outdatedItems.isEmpty ? "checkmark.circle" : "arrow.down.circle"),
                id: "summary", to: &entries)
        }
        if let needsAttentionSummary = state.needsAttentionSummary {
            appendDisabled(
                needsAttentionSummary, systemSymbolName: "exclamationmark.circle",
                id: "attention", to: &entries)
        }
        appendSeparator(to: &entries)

        let busyToolTip = "Another action is running."
        if progress == nil {
            appendAction(MenuBarMenuAction.checkNow.title, action: .menu(.checkNow), to: &entries)
            appendAction(
                MenuBarMenuAction.refreshStatus.title, action: .menu(.refreshStatus), to: &entries)
        } else {
            appendDisabled(
                MenuBarMenuAction.checkNow.title, toolTip: busyToolTip,
                systemSymbolName: MenuBarMenuAction.checkNow.systemSymbolName, to: &entries)
            appendDisabled(
                MenuBarMenuAction.refreshStatus.title, toolTip: busyToolTip,
                systemSymbolName: MenuBarMenuAction.refreshStatus.systemSymbolName, to: &entries)
        }

        let updateAllAction = MenuBarMenuAction.updateAllApprovedOutdated
        if progress != nil && supportsStopAfterCurrent {
            if isStopRequested {
                appendDisabled(
                    "Stopping after current…", systemSymbolName: "stop.circle",
                    id: "stop", to: &entries)
            } else {
                appendAction(
                    "Stop After Current",
                    action: .stopCurrentAction,
                    toolTip: "Lets running commands finish and starts nothing new.",
                    to: &entries
                )
            }
        } else if progress != nil {
            appendDisabled(
                updateAllAction.title, toolTip: busyToolTip,
                systemSymbolName: updateAllAction.systemSymbolName, to: &entries)
        } else if state.outdatedItems.isEmpty {
            appendDisabled(
                updateAllAction.title, toolTip: "No updates available.",
                systemSymbolName: updateAllAction.systemSymbolName, to: &entries)
        } else {
            appendAction(
                updateAllAction.title,
                action: .menu(updateAllAction),
                toolTip: "Updates all \(state.outdatedItems.count) approved outdated items.",
                to: &entries
            )
        }
        if let lastActionNotice, activeActionTitle == nil {
            appendDisabled(
                SecretRedactor.redact(lastActionNotice), systemSymbolName: "info.circle",
                id: "last-action", to: &entries)
        }
        appendSeparator(to: &entries)

        appendUpdates(activeUpdateItems ?? state.outdatedItems, progress: progress, to: &entries)
        appendApprovals(
            state.approvalItems,
            approvalStatuses: approvalStatuses,
            isBusy: progress != nil,
            to: &entries
        )
        appendErrors(state.errorItems, to: &entries)
        if entries.last == .separator {
            entries.removeLast()
        }
        entries.append(.updateHistory(updateHistory))

        appendSeparator(to: &entries)
        appendFooterActions(to: &entries)

        return MenuBarMenuModel(entries: entries)
    }

    private func appendFooterActions(to entries: inout [MenuBarMenuEntry]) {
        appendAction(
            MenuBarMenuAction.overview.title,
            action: .menu(.overview),
            to: &entries
        )
        entries.append(moreSubmenu())
        for action in [MenuBarMenuAction.checkForUpdates, .quit] {
            appendAction(action.title, action: .menu(action), to: &entries)
        }
    }

    private func moreSubmenu() -> MenuBarMenuEntry {
        .submenu(
            MenuBarSubmenu(
                title: "More",
                items: MenuBarMenuAction.more.map {
                    MenuBarMenuItem(
                        title: $0.title, action: .menu($0), systemSymbolName: $0.systemSymbolName)
                },
                systemSymbolName: "ellipsis.circle"
            )
        )
    }

    public func makeErrorMenu(errorDescription: String) -> MenuBarMenuModel {
        var entries: [MenuBarMenuEntry] = []
        appendDisabled("UpdateBar Error", to: &entries)
        appendDisabled(SecretRedactor.redact(errorDescription), to: &entries)
        appendSeparator(to: &entries)
        for action in [MenuBarMenuAction.refreshStatus, .checkNow] {
            appendAction(action.title, action: .menu(action), to: &entries)
        }
        appendFooterActions(to: &entries)
        return MenuBarMenuModel(entries: entries)
    }

    private func appendUpdates(
        _ items: [StatusItem],
        progress: MenuBarItemProgress?,
        to entries: inout [MenuBarMenuEntry]
    ) {
        appendSection(
            "Updates (\(items.count))", id: "updates", overflowTitle: "More Updates",
            items: items, to: &entries
        ) {
            item in
            let name = SecretRedactor.redact(item.name)
            let current = item.current.map(SecretRedactor.redact) ?? "?"
            let latest = item.latest.map(SecretRedactor.redact) ?? "?"
            let base = "\(name) \(current) -> \(latest)"

            guard let progress else {
                return MenuBarMenuItem(
                    title: base,
                    action: .update(id: item.id),
                    toolTip: "Updates \(SecretRedactor.redact(item.id)) immediately.",
                    systemSymbolName: "arrow.down.circle", id: "update:\(item.id)"
                )
            }
            if progress.inFlightIDs.contains(item.id) {
                return MenuBarMenuItem(
                    title: "\(base) — updating…",
                    systemSymbolName: "arrow.triangle.2.circlepath", id: "update:\(item.id)"
                )
            }
            if progress.finishedIDs.contains(item.id) {
                let result = progress.resultsByID[item.id]
                let label: String
                let symbol: String
                switch result?.outcome {
                case .failed?, .missing?:
                    (label, symbol) = ("failed", "exclamationmark.triangle")
                case .cancelled?:
                    (label, symbol) = ("stopped", "stop.circle")
                case .updated?, nil:
                    (label, symbol) = ("done", "checkmark.circle")
                default:
                    (label, symbol) = ("skipped", "minus.circle")
                }
                return MenuBarMenuItem(
                    title: "\(base) — \(label)", toolTip: result?.error.map(SecretRedactor.redact),
                    systemSymbolName: symbol,
                    id: "update:\(item.id)")
            }
            if progress.plannedIDs.contains(item.id) {
                return MenuBarMenuItem(
                    title: "\(base) — queued", systemSymbolName: "clock", id: "update:\(item.id)")
            }
            return MenuBarMenuItem(
                title: base, toolTip: "Another action is running.",
                systemSymbolName: "arrow.down.circle", id: "update:\(item.id)")
        }
    }

    private func appendApprovals(
        _ items: [StatusItem],
        approvalStatuses: [String: [CommandApprovalStatus]],
        isBusy: Bool,
        to entries: inout [MenuBarMenuEntry]
    ) {
        guard !items.isEmpty else { return }
        appendDisabled(
            "Command Approval Required (\(items.count))", id: "approvals", to: &entries)
        for item in sorted(items).prefix(Self.maxApprovalItems) {
            let approvals = approvalStatuses[item.id] ?? []
            if approvals.isEmpty {
                appendDisabled(
                    SecretRedactor.redact(item.name),
                    systemSymbolName: "questionmark.circle",
                    id: "approval:\(item.id)",
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
                        items: approvals.map {
                            approvalMenuItem(for: item, approval: $0, isBusy: isBusy)
                        },
                        systemSymbolName: systemSymbolName,
                        id: "approval:\(item.id)"
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
        approval: CommandApprovalStatus,
        isBusy: Bool
    ) -> MenuBarMenuItem {
        let verb = approval.approved ? "Revoke" : "Approve"
        let action: MenuBarMenuItemAction =
            approval.approved
            ? .revoke(id: item.id, reviewed: approval)
            : .approve(id: item.id, reviewed: approval)
        let confirmation = MenuBarActionConfirmation.commandApproval(
            for: item,
            status: approval
        )
        return MenuBarMenuItem(
            title: "\(verb) \(approvalFieldTitle(approval.field))",
            action: isBusy ? nil : action,
            toolTip: confirmation.toolTip,
            confirmation: confirmation,
            systemSymbolName: approval.approved ? "checkmark.circle" : "circle",
            id: approval.field
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
        appendSection(
            "Errors (\(items.count))", id: "errors", overflowTitle: "More Errors",
            items: items, to: &entries
        ) { item in
            let name = SecretRedactor.redact(item.name)
            let error = SecretRedactor.redact(item.error ?? "error")
            return MenuBarMenuItem(
                title: "\(name): \(error)", systemSymbolName: "exclamationmark.triangle",
                id: "error:\(item.id)")
        }
    }

    private func appendSection(
        _ title: String,
        id: String,
        overflowTitle: String,
        items: [StatusItem],
        to entries: inout [MenuBarMenuEntry],
        makeItem: (StatusItem) -> MenuBarMenuItem
    ) {
        guard !items.isEmpty else { return }
        appendDisabled(title, id: id, to: &entries)
        let orderedItems = sorted(items)
        for item in orderedItems.prefix(Self.maxSectionItems) {
            entries.append(.item(makeItem(item)))
        }
        let overflow = items.count - Self.maxSectionItems
        if overflow > 0 {
            entries.append(
                .submenu(
                    MenuBarSubmenu(
                        title: "\(overflowTitle) (\(overflow))",
                        items: orderedItems.dropFirst(Self.maxSectionItems).map(makeItem),
                        systemSymbolName: "list.bullet", id: "\(id)-overflow"
                    )))
        }
        appendSeparator(to: &entries)
    }

    private func sorted(_ items: [StatusItem]) -> [StatusItem] {
        items.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    private func appendDisabled(
        _ title: String,
        toolTip: String? = nil,
        systemSymbolName: String? = nil,
        id: String? = nil,
        to entries: inout [MenuBarMenuEntry]
    ) {
        entries.append(
            .item(
                MenuBarMenuItem(
                    title: title,
                    toolTip: toolTip,
                    systemSymbolName: systemSymbolName,
                    id: id
                )))
    }

    private func appendAction(
        _ title: String,
        action: MenuBarMenuItemAction,
        toolTip: String? = nil,
        confirmation: MenuBarActionConfirmation? = nil,
        to entries: inout [MenuBarMenuEntry]
    ) {
        let systemSymbolName: String?
        switch action {
        case .menu(let menuAction): systemSymbolName = menuAction.systemSymbolName
        case .stopCurrentAction: systemSymbolName = "stop.circle"
        default: systemSymbolName = nil
        }
        entries.append(
            .item(
                MenuBarMenuItem(
                    title: title,
                    action: action,
                    toolTip: toolTip,
                    confirmation: confirmation,
                    systemSymbolName: systemSymbolName,
                    id: action == .stopCurrentAction ? "stop" : nil
                )))
    }

    private func appendSeparator(to entries: inout [MenuBarMenuEntry]) {
        guard !entries.isEmpty, entries.last != .separator else { return }
        entries.append(.separator)
    }
}
