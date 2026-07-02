import Foundation

public struct CheckResult: Codable, Equatable {
    public var id: String
    public var name: String
    public var current: String?
    public var latest: String?
    public var status: ItemStatus
    public var lastChecked: Date?
    public var error: String?

    public init(
        id: String,
        name: String,
        current: String?,
        latest: String?,
        status: ItemStatus,
        lastChecked: Date?,
        error: String?
    ) {
        self.id = id
        self.name = name
        self.current = current.map(SecretRedactor.redact)
        self.latest = latest.map(SecretRedactor.redact)
        self.status = status
        self.lastChecked = lastChecked
        self.error = error.map(SecretRedactor.redact)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case current
        case latest
        case status
        case lastChecked = "last_checked"
        case error
    }
}
