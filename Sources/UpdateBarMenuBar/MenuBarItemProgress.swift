import UpdateBarCore

/// Per-item state of the running action, so the menu can annotate individual
/// rows instead of collapsing into a single "Updating…" line.
public struct MenuBarItemProgress: Equatable, Sendable {
    public var plannedIDs: [String] = []
    public var inFlightIDs: Set<String> = []
    public var finishedIDs: Set<String> = []

    public init() {}

    public var isEmpty: Bool {
        plannedIDs.isEmpty && inFlightIDs.isEmpty && finishedIDs.isEmpty
    }

    public var totalCount: Int { plannedIDs.count }
    public var completedCount: Int { finishedIDs.count }

    public mutating func apply(_ event: UpdateProgressEvent) {
        switch event {
        case .planned(let plan):
            plannedIDs = plan.map(\.id)
        case .itemStarted(let id, _):
            inFlightIDs.insert(id)
        case .itemFinished(let result):
            inFlightIDs.remove(result.id)
            finishedIDs.insert(result.id)
        }
    }
}
