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

    static func from(_ recipe: Recipe) -> [ApprovalStatus] {
        let commands = recipe.commandTexts()
        let workingDirectories = recipe.commandWorkingDirectories()
        return recipe.commandFingerprints().map { field, fingerprint in
            ApprovalStatus(
                field: field,
                approved: recipe.trust.level == .trusted
                    && recipe.trust.approvedCommands[field] == fingerprint,
                fingerprint: fingerprint,
                command: commands[field] ?? "",
                cwd: workingDirectories[field]
            )
        }.sorted { $0.field < $1.field }
    }
}
