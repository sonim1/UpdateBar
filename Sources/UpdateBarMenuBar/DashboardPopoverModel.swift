import Foundation
import UpdateBarCore

public struct DashboardPopoverRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let stateLabel: String

    public init(id: String, title: String, detail: String, stateLabel: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.stateLabel = stateLabel
    }
}

public struct DashboardPopoverModel: Equatable, Sendable {
    public let title: String
    public let trackedItemCount: Int
    public let updateCount: Int
    public let approvalCount: Int
    public let errorCount: Int
    public let lastChecked: Date?
    public let activeActionTitle: String?
    public let lastActionNotice: String?
    public let errorMessage: String?
    public let updates: [DashboardPopoverRow]
    public let approvals: [DashboardPopoverRow]
    public let errors: [DashboardPopoverRow]

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
        updates: [DashboardPopoverRow],
        approvals: [DashboardPopoverRow],
        errors: [DashboardPopoverRow]
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
    }
}

public struct DashboardPopoverModelBuilder: Sendable {
    public init() {}

    public func makeModel(
        state: MenuBarState,
        approvalStatuses: [String: [CommandApprovalStatus]],
        activeActionTitle: String? = nil,
        lastActionNotice: String? = nil,
        errorDescription: String? = nil
    ) -> DashboardPopoverModel {
        let sourceItems =
            state.allItems.isEmpty
            ? state.outdatedItems + state.approvalItems + state.errorItems + state.okItems
            : state.allItems
        let updates = state.outdatedItems.map { item in
            DashboardPopoverRow(
                id: "update-\(item.id)",
                title: SecretRedactor.redact(item.name),
                detail: SecretRedactor.redact(
                    "\(item.current ?? "?") -> \(item.latest ?? "?")"
                ),
                stateLabel: "Ready"
            )
        }
        let approvals = state.approvalItems.flatMap { item in
            let statuses = approvalStatuses[item.id] ?? []
            if statuses.isEmpty {
                return [
                    DashboardPopoverRow(
                        id: "approval-\(item.id)",
                        title: SecretRedactor.redact(item.name),
                        detail: "No command fields",
                        stateLabel: "Needs approval"
                    )
                ]
            }
            return statuses.map { status in
                DashboardPopoverRow(
                    id: "approval-\(item.id)-\(status.field)",
                    title: SecretRedactor.redact(item.name),
                    detail: SecretRedactor.redact("\(status.field): \(status.command)"),
                    stateLabel: status.approved ? "Approved" : "Needs approval"
                )
            }
        }
        let errors = state.errorItems.map { item in
            DashboardPopoverRow(
                id: "error-\(item.id)",
                title: SecretRedactor.redact(item.name),
                detail: SecretRedactor.redact(item.error ?? "Unknown error"),
                stateLabel: "Error"
            )
        }

        return DashboardPopoverModel(
            title: state.title,
            trackedItemCount: Set(sourceItems.map(\.id)).count,
            updateCount: state.outdatedItems.count,
            approvalCount: state.approvalItems.count,
            errorCount: state.errorItems.count,
            lastChecked: sourceItems.compactMap(\.lastChecked).max(),
            activeActionTitle: activeActionTitle.map(SecretRedactor.redact),
            lastActionNotice: lastActionNotice.map(SecretRedactor.redact),
            errorMessage: errorDescription.map(SecretRedactor.redact),
            updates: updates,
            approvals: approvals,
            errors: errors
        )
    }
}
