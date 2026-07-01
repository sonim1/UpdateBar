import Foundation

public struct StatusSnapshot: Codable, Equatable {
    public var generatedAt: Date
    public var summary: StatusSummary
    public var items: [StatusItem]

    public static func from(manifest: Manifest, state: State, now: Date) -> StatusSnapshot {
        let items = manifest.items.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name
        }.map { recipe -> StatusItem in
            let itemState = state.items[recipe.id]
            let status = resolvedStatus(recipe: recipe, itemState: itemState)
            return StatusItem(
                id: recipe.id,
                name: recipe.name,
                category: recipe.category,
                current: itemState?.current,
                latest: itemState?.latest,
                status: status,
                pinned: recipe.pin != nil,
                lastChecked: itemState?.lastChecked,
                error: status == .error ? itemState?.error : nil
            )
        }

        return StatusSnapshot(
            generatedAt: now,
            summary: StatusSummary(
                total: items.count,
                outdated: items.filter { $0.status == .outdated }.count,
                errors: items.filter { $0.status == .error }.count,
                untrusted: items.filter { $0.status == .untrusted }.count,
                pinned: items.filter { $0.status == .pinned }.count
            ),
            items: items
        )
    }

    private static func resolvedStatus(recipe: Recipe, itemState: ItemState?) -> ItemStatus {
        if !recipe.enabled { return .disabled }
        if recipe.pin != nil { return .pinned }
        if recipe.trust.level == .untrusted || recipe.trust.level == .elevated {
            return .untrusted
        }
        guard let itemState else { return .checking }
        if itemState.status == .error { return .error }
        if itemState.status == .checking { return .checking }
        return itemState.status
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case summary
        case items
    }
}

public struct StatusSummary: Codable, Equatable {
    public var total: Int
    public var outdated: Int
    public var errors: Int
    public var untrusted: Int
    public var pinned: Int

    public init(total: Int, outdated: Int, errors: Int, untrusted: Int = 0, pinned: Int = 0) {
        self.total = total
        self.outdated = outdated
        self.errors = errors
        self.untrusted = untrusted
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey {
        case total
        case outdated
        case errors
        case untrusted
        case pinned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decode(Int.self, forKey: .total)
        outdated = try container.decode(Int.self, forKey: .outdated)
        errors = try container.decode(Int.self, forKey: .errors)
        untrusted = try container.decodeIfPresent(Int.self, forKey: .untrusted) ?? 0
        pinned = try container.decodeIfPresent(Int.self, forKey: .pinned) ?? 0
    }
}

public struct StatusItem: Codable, Equatable {
    public var id: String
    public var name: String
    public var category: String
    public var current: String?
    public var latest: String?
    public var status: ItemStatus
    public var pinned: Bool
    public var lastChecked: Date?
    public var error: String?

    public init(
        id: String,
        name: String,
        category: String,
        current: String?,
        latest: String?,
        status: ItemStatus,
        pinned: Bool,
        lastChecked: Date?,
        error: String?
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.current = current
        self.latest = latest
        self.status = status
        self.pinned = pinned
        self.lastChecked = lastChecked
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case current
        case latest
        case status
        case pinned
        case lastChecked = "last_checked"
        case error
    }
}
