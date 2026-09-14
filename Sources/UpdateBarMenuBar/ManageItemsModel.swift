import Foundation
import UpdateBarCore

public enum ManageItemsSectionKind: CaseIterable, Equatable, Sendable {
    case ready
    case review
    case attention
    case current
    case paused

    public var title: String {
        switch self {
        case .ready: "Ready to update"
        case .review: "Needs review"
        case .attention: "Needs attention"
        case .current: "Up to date"
        case .paused: "Paused"
        }
    }

    public var subtitle: String {
        switch self {
        case .ready: "Approved commands. You choose what runs."
        case .review: "Review command access before an update can run."
        case .attention: "These tools need a check or your attention."
        case .current: "No update is available."
        case .paused: "Disabled or pinned tools do not update."
        }
    }

    public var systemImage: String {
        switch self {
        case .ready: "arrow.down.to.line"
        case .review: "checkmark.shield"
        case .attention: "exclamationmark.triangle"
        case .current: "checkmark"
        case .paused: "pause"
        }
    }
}

public struct ManageItemsSection: Equatable {
    public var kind: ManageItemsSectionKind
    public var items: [StatusItem]
    public var isExpanded: Bool

    public init(kind: ManageItemsSectionKind, items: [StatusItem], isExpanded: Bool) {
        self.kind = kind
        self.items = items
        self.isExpanded = isExpanded
    }
}

public struct ManageItemsPrimaryAction: Equatable, Sendable {
    public var title: String
    public var ids: [String]

    public init(title: String, ids: [String]) {
        self.title = title
        self.ids = ids
    }
}

public struct ManageItemsSelectionModel: Equatable, Sendable {
    public private(set) var query = ""
    private var selected: [String: VersionIdentity] = [:]

    public init() {}

    public var selectedIDs: [String] { selected.keys.sorted() }

    public func contains(_ id: String) -> Bool {
        selected[id] != nil
    }

    public mutating func toggle(item: StatusItem, in model: MenuBarPopoverModel) {
        guard model.eligibleItems.contains(where: { $0.id == item.id }) else { return }
        if selected.removeValue(forKey: item.id) == nil {
            selected[item.id] = VersionIdentity(current: item.current, latest: item.latest)
        }
    }

    public mutating func setQuery(_ query: String) {
        if query != self.query { selected.removeAll() }
        self.query = query
    }

    public mutating func clear() {
        selected.removeAll()
    }

    public mutating func reconcile(
        with model: MenuBarPopoverModel,
        visibleIDs: Set<String>? = nil
    ) {
        let eligible = Dictionary(uniqueKeysWithValues: model.eligibleItems.map { ($0.id, $0) })
        selected = selected.filter { id, identity in
            guard let item = eligible[id], visibleIDs?.contains(id) != false else { return false }
            return identity == VersionIdentity(current: item.current, latest: item.latest)
        }
    }

    private struct VersionIdentity: Equatable, Sendable {
        var current: String?
        var latest: String?
    }
}

public struct ManageItemsModel: Sendable {
    public init() {}

    public func sections(from model: MenuBarPopoverModel, query: String) -> [ManageItemsSection] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingItems = model.state.allItems.filter { matches($0, query: normalizedQuery) }
        let reviewIDs = Set((model.approvalItems + model.readyToCheckItems).map(\.id))
        let eligibleIDs = Set(model.eligibleItems.map(\.id))
        let activeIDs = model.isUpdating ? Set(model.progress.plannedIDs) : []
        let grouped = Dictionary(grouping: matchingItems) { item in
            sectionKind(
                for: item, reviewIDs: reviewIDs, eligibleIDs: eligibleIDs,
                activeIDs: activeIDs
            )
        }

        return ManageItemsSectionKind.allCases.map { kind in
            let items = (grouped[kind] ?? []).sorted {
                let names = $0.name.localizedCaseInsensitiveCompare($1.name)
                return names == .orderedSame ? $0.id < $1.id : names == .orderedAscending
            }
            return ManageItemsSection(
                kind: kind, items: items,
                isExpanded: !normalizedQuery.isEmpty || (kind != .current && kind != .paused)
            )
        }
    }

    public func primaryAction(
        from model: MenuBarPopoverModel,
        query: String,
        selectedIDs: [String]
    ) -> ManageItemsPrimaryAction {
        let eligible = model.eligibleItems
        let eligibleIDs = Set(eligible.map(\.id))
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleEligible = eligible.filter { matches($0, query: normalizedQuery) }
        let visibleEligibleIDs = Set(visibleEligible.map(\.id))
        let selected = selectedIDs.filter {
            eligibleIDs.contains($0) && visibleEligibleIDs.contains($0)
        }.sorted()
        if !selected.isEmpty {
            return ManageItemsPrimaryAction(
                title: "Update selected (\(selected.count))", ids: selected
            )
        }

        let targets = visibleEligible.map(\.id).sorted()
        let scope = normalizedQuery.isEmpty ? "all" : "visible"
        return ManageItemsPrimaryAction(title: "Update \(scope) (\(targets.count))", ids: targets)
    }

    public func statusText(for item: StatusItem, in model: MenuBarPopoverModel) -> String {
        let phase = phase(for: item, in: model)
        if phase != .idle { return phase.title }
        switch item.status {
        case .ok: return item.current ?? "Up to date"
        case .outdated: return versionText(for: item)
        case .untrusted:
            return model.readyToCheckItems.contains(where: { $0.id == item.id })
                ? "Approved. Check for updates." : "Command approval required"
        case .disabled: return "Disabled"
        case .pinned: return item.current.map { "Pinned to \($0)" } ?? "Pinned"
        case .checking: return "Checking"
        case .differs: return "Installed version differs"
        case .error: return item.error ?? "Check failed"
        }
    }

    public func phase(for item: StatusItem, in model: MenuBarPopoverModel)
        -> MenuBarPopoverItemPhase
    {
        let phase = model.phase(for: item.id)
        guard let result = model.progress.resultsByID[item.id] else { return phase }
        guard result.current == item.current, result.latest == item.latest else { return .idle }
        return phase
    }

    public func versionText(for item: StatusItem) -> String {
        switch (item.current, item.latest) {
        case (let current?, let latest?): "\(current)  →  \(latest)"
        case (let current?, nil): current
        case (nil, let latest?): latest
        case (nil, nil): "Version unavailable"
        }
    }

    private func sectionKind(
        for item: StatusItem,
        reviewIDs: Set<String>,
        eligibleIDs: Set<String>,
        activeIDs: Set<String>
    ) -> ManageItemsSectionKind {
        if item.pinned || item.status == .pinned || item.status == .disabled { return .paused }
        if reviewIDs.contains(item.id) || item.status == .untrusted { return .review }
        if activeIDs.contains(item.id) || eligibleIDs.contains(item.id) { return .ready }
        switch item.status {
        case .ok: return .current
        case .error, .differs, .checking: return .attention
        case .outdated, .untrusted, .pinned, .disabled: return .attention
        }
    }

    private func matches(_ item: StatusItem, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [item.id, item.name, item.category, item.current ?? "", item.latest ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
