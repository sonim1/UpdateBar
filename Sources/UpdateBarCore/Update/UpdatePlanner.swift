import Foundation

public struct UpdatePlanner {
    private let manifest: Manifest
    private let state: State

    public init(manifest: Manifest, state: State) {
        self.manifest = manifest
        self.state = state
    }

    public func plan(ids: [String], all: Bool) -> [UpdatePlanItem] {
        if !all, ids.isEmpty {
            return []
        }

        if ids.isEmpty {
            return manifest.items.map { plan(recipe: $0) }
        }

        return ids.map { id in
            guard let recipe = manifest.item(id: id) else {
                return UpdatePlanItem(
                    id: id,
                    name: id,
                    decision: .missing,
                    current: nil,
                    latest: nil,
                    commandFingerprint: nil
                )
            }
            return plan(recipe: recipe)
        }
    }

    private func plan(recipe: Recipe) -> UpdatePlanItem {
        let itemState = state.items[recipe.id]
        let decision: UpdatePlanDecision
        if !recipe.enabled {
            decision = .skippedDisabled
        } else if recipe.pin != nil {
            decision = .skippedPinned
        } else if !TrustPolicy.isApproved(recipe, field: "update.cmd") {
            decision = .skippedUntrusted
        } else if itemState?.status != .outdated {
            decision = .skippedNotOutdated
        } else {
            decision = .willUpdate
        }

        return UpdatePlanItem(
            id: recipe.id,
            name: recipe.name,
            decision: decision,
            current: itemState?.current,
            latest: itemState?.latest,
            commandFingerprint: recipe.commandFingerprints()["update.cmd"]
        )
    }
}

public struct UpdatePlanItem: Codable, Equatable {
    public var id: String
    public var name: String
    public var decision: UpdatePlanDecision
    public var current: String?
    public var latest: String?
    public var commandFingerprint: String?

    public init(
        id: String,
        name: String,
        decision: UpdatePlanDecision,
        current: String?,
        latest: String?,
        commandFingerprint: String?
    ) {
        self.id = id
        self.name = name
        self.decision = decision
        self.current = current
        self.latest = latest
        self.commandFingerprint = commandFingerprint
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case decision
        case current
        case latest
        case commandFingerprint = "command_fingerprint"
    }
}

public enum UpdatePlanDecision: String, Codable, Equatable {
    case willUpdate = "will_update"
    case skippedPinned = "skipped_pinned"
    case skippedDisabled = "skipped_disabled"
    case skippedUntrusted = "skipped_untrusted"
    case skippedNotOutdated = "skipped_not_outdated"
    case missing
}
