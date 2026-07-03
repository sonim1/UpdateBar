public struct CheckReport: Codable, Equatable {
    public var summary: CheckSummary
    public var results: [CheckResult]

    public init(results: [CheckResult]) {
        self.summary = CheckSummary(results: results)
        self.results = results
    }
}

public struct CheckSummary: Codable, Equatable {
    public var total: Int
    public var outdated: Int
    public var errors: Int
    public var untrusted: Int
    public var disabled: Int
    public var pinned: Int
    public var differs: Int

    enum CodingKeys: String, CodingKey {
        case total
        case outdated
        case errors
        case untrusted
        case disabled
        case pinned
        case differs
    }

    public init(results: [CheckResult]) {
        self.total = results.count
        self.outdated = results.filter { $0.status == .outdated }.count
        self.errors = results.filter { $0.status == .error }.count
        self.untrusted = results.filter { $0.status == .untrusted }.count
        self.disabled = results.filter { $0.status == .disabled }.count
        self.pinned = results.filter { $0.status == .pinned }.count
        self.differs = results.filter { $0.status == .differs }.count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decode(Int.self, forKey: .total)
        outdated = try container.decode(Int.self, forKey: .outdated)
        errors = try container.decode(Int.self, forKey: .errors)
        untrusted = try container.decode(Int.self, forKey: .untrusted)
        disabled = try container.decode(Int.self, forKey: .disabled)
        pinned = try container.decode(Int.self, forKey: .pinned)
        differs = try container.decodeIfPresent(Int.self, forKey: .differs) ?? 0
        try validateNonNegativeDecoded(total, forKey: .total, in: container)
        try validateNonNegativeDecoded(outdated, forKey: .outdated, in: container)
        try validateNonNegativeDecoded(errors, forKey: .errors, in: container)
        try validateNonNegativeDecoded(untrusted, forKey: .untrusted, in: container)
        try validateNonNegativeDecoded(disabled, forKey: .disabled, in: container)
        try validateNonNegativeDecoded(pinned, forKey: .pinned, in: container)
        try validateNonNegativeDecoded(differs, forKey: .differs, in: container)
    }
}
