public struct ApprovalStatus: Codable, Equatable, Sendable {
    public var field: String
    public var approved: Bool
    public var fingerprint: String
    public var command: String
    public var cwd: String?

    public init(
        field: String,
        approved: Bool,
        fingerprint: String,
        command: String,
        cwd: String?
    ) {
        self.field = field
        self.approved = approved
        self.fingerprint = fingerprint
        self.command = command
        self.cwd = cwd
    }
}
