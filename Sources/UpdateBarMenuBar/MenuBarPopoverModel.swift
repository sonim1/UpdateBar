import Foundation
import UpdateBarCore

public struct MenuBarPopoverRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let stateLabel: String
    public let action: MenuBarMenuItemAction?
    public let confirmation: MenuBarActionConfirmation?

    public init(
        id: String,
        title: String,
        detail: String,
        stateLabel: String,
        action: MenuBarMenuItemAction?,
        confirmation: MenuBarActionConfirmation?
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.stateLabel = stateLabel
        self.action = action
        self.confirmation = confirmation
    }
}

public struct MenuBarPopoverModel: Equatable, Sendable {
    public let title: String
    public let trackedItemCount: Int
    public let updateCount: Int
    public let approvalCount: Int
    public let errorCount: Int
    public let lastChecked: Date?
    public let activeActionTitle: String?
    public let lastActionNotice: String?
    public let errorMessage: String?
    public let updates: [MenuBarPopoverRow]
    public let approvals: [MenuBarPopoverRow]
    public let errors: [MenuBarPopoverRow]
    public let terminals: [TUITerminal]
    public let selectedTerminalID: String?

    public init(
        title: String,
        trackedItemCount: Int,
        updateCount: Int,
        approvalCount: Int,
        errorCount: Int,
        lastChecked: Date?,
        activeActionTitle: String?,
        lastActionNotice: String?,
        errorMessage: String?,
        updates: [MenuBarPopoverRow],
        approvals: [MenuBarPopoverRow],
        errors: [MenuBarPopoverRow],
        terminals: [TUITerminal],
        selectedTerminalID: String?
    ) {
        self.title = title
        self.trackedItemCount = trackedItemCount
        self.updateCount = updateCount
        self.approvalCount = approvalCount
        self.errorCount = errorCount
        self.lastChecked = lastChecked
        self.activeActionTitle = activeActionTitle
        self.lastActionNotice = lastActionNotice
        self.errorMessage = errorMessage
        self.updates = updates
        self.approvals = approvals
        self.errors = errors
        self.terminals = terminals
        self.selectedTerminalID = selectedTerminalID
    }
}

public struct MenuBarPopoverModelBuilder: Sendable {
    public init() {}

    public func makeModel(
        state: MenuBarState,
        approvalStatuses: [String: [CommandApprovalStatus]],
        activeActionTitle: String? = nil,
        lastActionNotice: String? = nil,
        errorDescription: String? = nil,
        installedTerminals: [TUITerminal] = [],
        selectedTerminalID: String? = nil
    ) -> MenuBarPopoverModel {
        let sourceItems =
            state.allItems.isEmpty
            ? state.outdatedItems + state.approvalItems + state.errorItems + state.okItems
            : state.allItems
        let trackedIDs = Set(sourceItems.map(\.id))
        let updates = state.outdatedItems.map { item in
            let action = MenuBarMenuItemAction.update(id: item.id)
            return MenuBarPopoverRow(
                id: "update-\(item.id)",
                title: SecretRedactor.redact(item.name),
                detail: SecretRedactor.redact(
                    "\(item.current ?? "?") -> \(item.latest ?? "?")"
                ),
                stateLabel: "Ready",
                action: action,
                confirmation: MenuBarActionConfirmation.updateItem(
                    for: item,
                    approvalStatuses: approvalStatuses
                )
            )
        }
        let approvals = state.approvalItems.flatMap { item in
            let statuses = approvalStatuses[item.id] ?? []
            if statuses.isEmpty {
                return [
                    MenuBarPopoverRow(
                        id: "approval-\(item.id)",
                        title: SecretRedactor.redact(item.name),
                        detail: "No command fields",
                        stateLabel: "Needs approval",
                        action: nil,
                        confirmation: nil
                    )
                ]
            }
            return statuses.map { approval in
                let action: MenuBarMenuItemAction =
                    approval.approved
                    ? .revoke(id: item.id, field: approval.field)
                    : .approve(id: item.id, field: approval.field)
                return MenuBarPopoverRow(
                    id: "approval-\(item.id)-\(approval.field)",
                    title: SecretRedactor.redact(item.name),
                    detail: SecretRedactor.redact(
                        "\(approval.field): \(approval.command)"
                    ),
                    stateLabel: approval.approved ? "Approved" : "Needs approval",
                    action: action,
                    confirmation: MenuBarActionConfirmation.commandApproval(
                        for: item,
                        status: approval
                    )
                )
            }
        }
        let errors = state.errorItems.map { item in
            MenuBarPopoverRow(
                id: "error-\(item.id)",
                title: SecretRedactor.redact(item.name),
                detail: SecretRedactor.redact(item.error ?? "Unknown error"),
                stateLabel: "Error",
                action: nil,
                confirmation: nil
            )
        }
        return MenuBarPopoverModel(
            title: state.title,
            trackedItemCount: trackedIDs.count,
            updateCount: state.outdatedItems.count,
            approvalCount: state.approvalItems.count,
            errorCount: state.errorItems.count,
            lastChecked: sourceItems.compactMap(\.lastChecked).max(),
            activeActionTitle: activeActionTitle.map(SecretRedactor.redact),
            lastActionNotice: lastActionNotice.map(SecretRedactor.redact),
            errorMessage: errorDescription.map(SecretRedactor.redact),
            updates: updates,
            approvals: approvals,
            errors: errors,
            terminals: installedTerminals,
            selectedTerminalID: selectedTerminalID
        )
    }
}
