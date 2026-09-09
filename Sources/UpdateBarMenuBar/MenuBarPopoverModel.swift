import Foundation
import UpdateBarCore

public enum MenuBarPopoverItemPhase: Equatable {
    case idle
    case queued
    case running
    case succeeded
    case failed
    case skipped
    case cancelled
    case notStarted

    public var title: String {
        switch self {
        case .idle: "Update available"
        case .queued: "Queued"
        case .running: "Running"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .skipped: "Skipped"
        case .cancelled: "Cancelled"
        case .notStarted: "Not started"
        }
    }
}

public struct MenuBarPopoverModel: Equatable {
    public private(set) var state = MenuBarState(
        title: "UpdateBar", badgeValue: nil, outdatedItems: [], approvalItems: [],
        errorItems: [], okItems: []
    )
    public private(set) var approvals: [String: [CommandApprovalStatus]] = [:]
    public private(set) var progress = MenuBarItemProgress()
    public private(set) var activeActionTitle: String?
    public private(set) var isUpdateAction = false
    public private(set) var isRefreshing = true
    public private(set) var stopRequested = false
    public private(set) var notice: String?
    public private(set) var errorMessage: String?
    public private(set) var detailItemID: String?

    private var selectionChoices: [String: SelectionChoice] = [:]
    private var acknowledgements: [String: [String: Acknowledgement]] = [:]

    public init() {}

    public var isBusy: Bool { activeActionTitle != nil || isRefreshing }
    public var isUpdating: Bool { activeActionTitle != nil && isUpdateAction }
    public var isFirstRun: Bool { state.allItems.isEmpty }
    public var lastChecked: Date? { state.allItems.compactMap(\.lastChecked).max() }

    public var isAllCurrent: Bool {
        !state.allItems.isEmpty && approvalItems.isEmpty
            && state.allItems.allSatisfy { $0.status == .ok }
    }

    public var eligibleItems: [StatusItem] {
        state.allItems.filter { $0.status == .outdated && isAllowedToRun($0) }
    }

    public var selectedIDs: [String] {
        eligibleItems.filter { selectionChoices[$0.id]?.isSelected == true }.map(\.id)
    }

    public var approvalItems: [StatusItem] {
        let attentionIDs = Set(state.approvalItems.map(\.id))
        return state.allItems.filter { item in
            if let commands = approvals[item.id], !commands.isEmpty {
                return commands.contains { !$0.approved }
            }
            return item.status == .untrusted || attentionIDs.contains(item.id)
        }
    }

    public var readyToCheckItems: [StatusItem] {
        state.allItems.filter { item in
            guard item.status == .untrusted, !item.pinned,
                let commands = approvals[item.id], !commands.isEmpty
            else { return false }
            return commands.allSatisfy(\.approved)
        }
    }

    public var errorItems: [StatusItem] {
        state.allItems.filter { $0.status == .error }
    }

    public var detailItem: StatusItem? {
        state.allItems.first { $0.id == detailItemID }
    }

    public var retryIDs: [String] {
        let allowedIDs = Set(state.allItems.filter(isAllowedToRun).map(\.id))
        return progress.failedIDs.filter { allowedIDs.contains($0) }
    }

    public var stopMessage: String {
        let runningCount = progress.inFlightIDs.count
        if runningCount == 0 {
            return "Stopping. Active commands will finish; no new updates will start."
        }
        let noun = runningCount == 1 ? "command finishes" : "commands finish"
        return "Stopping after \(runningCount) active \(noun). No new updates will start."
    }

    public mutating func update(
        state: MenuBarState,
        approvals: [String: [CommandApprovalStatus]],
        progress: MenuBarItemProgress = MenuBarItemProgress(),
        activeActionTitle: String? = nil,
        isUpdateAction: Bool = false,
        isRefreshing: Bool = false,
        stopRequested: Bool = false,
        notice: String? = nil,
        errorMessage: String? = nil
    ) {
        self.state = state
        self.approvals = approvals
        self.progress = progress
        self.activeActionTitle = activeActionTitle.map(SecretRedactor.redact)
        self.isUpdateAction = isUpdateAction
        self.isRefreshing = isRefreshing
        self.stopRequested = stopRequested
        self.notice = notice.map(SecretRedactor.redact)
        self.errorMessage = errorMessage.map(SecretRedactor.redact)

        let existingIDs = Set(state.allItems.map(\.id))
        selectionChoices = selectionChoices.filter { existingIDs.contains($0.key) }
        for item in eligibleItems {
            if let choice = selectionChoices[item.id],
                choice.current == item.current, choice.latest == item.latest
            {
                continue
            }
            selectionChoices[item.id] = SelectionChoice(
                current: item.current, latest: item.latest, isSelected: true
            )
        }
        if detailItem == nil {
            detailItemID = nil
        }
        for id in Array(acknowledgements.keys) {
            acknowledgements[id] = acknowledgements[id]?.filter { field, previous in
                acknowledgement(id: id, field: field) == previous
            }
            if acknowledgements[id]?.isEmpty == true {
                acknowledgements[id] = nil
            }
        }
    }

    public mutating func setSelected(_ selected: Bool, id: String) {
        guard !isBusy, eligibleItems.contains(where: { $0.id == id }) else { return }
        selectionChoices[id]?.isSelected = selected
    }

    public mutating func showDetails(id: String) {
        guard state.allItems.contains(where: { $0.id == id }) else { return }
        detailItemID = id
    }

    public mutating func showList() {
        detailItemID = nil
    }

    public mutating func setAcknowledged(_ acknowledged: Bool, id: String, field: String) {
        guard !isBusy else { return }
        if acknowledged, let current = acknowledgement(id: id, field: field) {
            acknowledgements[id, default: [:]][field] = current
        } else {
            acknowledgements[id]?[field] = nil
        }
    }

    public func isAcknowledged(id: String, field: String) -> Bool {
        guard let current = acknowledgement(id: id, field: field) else { return false }
        return acknowledgements[id]?[field] == current
    }

    public func reviewedApproval(id: String, field: String) -> CommandApprovalStatus? {
        guard !isBusy,
            let current = approvals[id]?.first(where: { $0.field == field }),
            current.approved || isAcknowledged(id: id, field: field)
        else { return nil }
        return current
    }

    public func phase(for id: String) -> MenuBarPopoverItemPhase {
        if isUpdating && progress.inFlightIDs.contains(id) {
            return .running
        }
        if let result = progress.resultsByID[id] {
            switch result.outcome {
            case .updated: return .succeeded
            case .failed, .missing: return .failed
            case .cancelled: return .cancelled
            case .skippedPinned, .skippedDisabled, .skippedUntrusted, .skippedNotOutdated:
                return .skipped
            }
        }
        if progress.plannedIDs.contains(id) {
            return isUpdating && !stopRequested ? .queued : .notStarted
        }
        return .idle
    }

    public func item(for id: String) -> StatusItem? {
        state.allItems.first { $0.id == id }
    }

    private func isAllowedToRun(_ item: StatusItem) -> Bool {
        !item.pinned && item.status != .pinned && item.status != .disabled
            && item.status != .untrusted
            && !state.approvalItems.contains(where: { $0.id == item.id })
            && approvals[item.id]?.contains(where: { !$0.approved }) != true
    }

    private func acknowledgement(id: String, field: String) -> Acknowledgement? {
        guard let item = item(for: id),
            let command = approvals[id]?.first(where: { $0.field == field })
        else { return nil }
        return Acknowledgement(itemStatus: item.status, command: command)
    }

    private struct Acknowledgement: Equatable {
        var itemStatus: ItemStatus
        var command: CommandApprovalStatus
    }

    private struct SelectionChoice: Equatable {
        var current: String?
        var latest: String?
        var isSelected: Bool
    }
}
