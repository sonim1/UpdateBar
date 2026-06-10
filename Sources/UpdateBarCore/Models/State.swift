import Foundation

public struct State: Codable, Equatable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var items: [String: ItemState]

    public init(schemaVersion: Int, generatedAt: Date, items: [String: ItemState]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case items
    }
}

public struct ItemState: Codable, Equatable {
    public var current: String?
    public var latest: String?
    public var status: ItemStatus
    public var lastChecked: Date?
    public var error: String?
    public var backoffUntil: Date?

    public init(
        current: String?,
        latest: String?,
        status: ItemStatus,
        lastChecked: Date?,
        error: String?,
        backoffUntil: Date?
    ) {
        self.current = current
        self.latest = latest
        self.status = status
        self.lastChecked = lastChecked
        self.error = error
        self.backoffUntil = backoffUntil
    }

    enum CodingKeys: String, CodingKey {
        case current
        case latest
        case status
        case lastChecked = "last_checked"
        case error
        case backoffUntil = "backoff_until"
    }
}

public enum ItemStatus: String, Codable, Equatable {
    case ok
    case outdated
    case differs
    case error
    case pinned
    case disabled
    case checking
    case untrusted
}
