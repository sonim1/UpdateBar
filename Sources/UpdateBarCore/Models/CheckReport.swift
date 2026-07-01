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

    public init(results: [CheckResult]) {
        self.total = results.count
        self.outdated = results.filter { $0.status == .outdated }.count
        self.errors = results.filter { $0.status == .error }.count
        self.untrusted = results.filter { $0.status == .untrusted }.count
        self.disabled = results.filter { $0.status == .disabled }.count
        self.pinned = results.filter { $0.status == .pinned }.count
    }
}
