import UpdateBarCore

/// Per-item state of the running action, so the menu can annotate individual
/// rows instead of collapsing into a single "Updating…" line.
public struct MenuBarItemProgress: Equatable, Sendable {
    public var plannedIDs: [String] = [] {
        didSet { plannedLookup = Set(plannedIDs) }
    }
    public var inFlightIDs: Set<String> = []
    public var finishedIDs: Set<String> = []

    private var plannedLookup: Set<String> = []

    public init() {}

    public var isEmpty: Bool {
        plannedIDs.isEmpty && inFlightIDs.isEmpty && finishedIDs.isEmpty
    }

    public var totalCount: Int { plannedIDs.count }
    public var completedCount: Int { finishedIDs.count }

    public mutating func apply(_ event: UpdateProgressEvent) {
        switch event {
        case .planned(let plan):
            // The planner returns every manifest item, most of them up to
            // date. Only the ones that will actually run belong in the
            // counter, otherwise the menu opens at "(47/50)".
            plannedIDs = plan.filter { $0.decision == .willUpdate }.map(\.id)
        case .itemStarted(let id, _):
            guard plannedLookup.contains(id) else { return }
            inFlightIDs.insert(id)
        case .itemFinished(let result):
            guard plannedLookup.contains(result.id) else { return }
            inFlightIDs.remove(result.id)
            finishedIDs.insert(result.id)
        }
    }
}
