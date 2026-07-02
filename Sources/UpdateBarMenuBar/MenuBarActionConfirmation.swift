public struct MenuBarActionConfirmation: Equatable, Sendable {
    public var title: String
    public var message: String
    public var toolTip: String
    public var confirmButton: String
    public var cancelButton: String

    public init(
        title: String,
        message: String,
        toolTip: String,
        confirmButton: String,
        cancelButton: String = "Cancel"
    ) {
        self.title = title
        self.message = message
        self.toolTip = toolTip
        self.confirmButton = confirmButton
        self.cancelButton = cancelButton
    }

    public static func confirmation(for action: MenuBarMenuAction) -> MenuBarActionConfirmation? {
        switch action {
        case .updateAllApprovedOutdated:
            return MenuBarActionConfirmation(
                title: "Run Updates?",
                message: "This runs update commands for approved outdated items.",
                toolTip: "Runs approved outdated items after confirmation.",
                confirmButton: "Run Updates"
            )
        case .checkNow, .openTUI, .openConfig, .viewLogs, .quit:
            return nil
        }
    }

    public static func updateAllApprovedOutdated(itemNames: [String]) -> MenuBarActionConfirmation {
        let count = itemNames.count
        let itemNoun = count == 1 ? "item" : "items"
        let updateNoun = count == 1 ? "Update" : "Updates"
        var message = "This runs update commands for \(count) approved outdated \(itemNoun)."
        let visibleNames = itemNames.prefix(6)
        if !visibleNames.isEmpty {
            message += "\n\nItems:\n"
            message += visibleNames.map { "- \($0)" }.joined(separator: "\n")
            let hidden = itemNames.count - visibleNames.count
            if hidden > 0 {
                message += "\n- and \(hidden) more"
            }
        }
        return MenuBarActionConfirmation(
            title: "Run \(count) \(updateNoun)?",
            message: message,
            toolTip: "Runs \(count) approved outdated \(itemNoun) after confirmation.",
            confirmButton: "Run Updates"
        )
    }

    public static func updateItem(
        id: String,
        command: String? = nil,
        cwd: String? = nil
    ) -> MenuBarActionConfirmation {
        var message = "This runs the update command for \(id)."
        if let command, !command.isEmpty {
            message += "\n\nCommand:\n\(command)"
        }
        if let cwd, !cwd.isEmpty {
            message += "\n\nWorking directory:\n\(cwd)"
        }
        return MenuBarActionConfirmation(
            title: "Update \(id)?",
            message: message,
            toolTip: "Runs \(id) after confirmation.",
            confirmButton: "Update"
        )
    }

    public static func commandApproval(
        id: String,
        field: String,
        approving: Bool,
        command: String? = nil,
        cwd: String? = nil
    ) -> MenuBarActionConfirmation {
        let verb = approving ? "Approve" : "Revoke"
        let sentenceVerb = approving ? "approves" : "revokes"
        var message = "This \(sentenceVerb) \(field) for \(id)."
        if let command, !command.isEmpty {
            message += "\n\nCommand:\n\(command)"
        }
        if let cwd, !cwd.isEmpty {
            message += "\n\nWorking directory:\n\(cwd)"
        }
        return MenuBarActionConfirmation(
            title: "\(verb) \(field)?",
            message: message,
            toolTip: "\(verb)s \(field) for \(id) after confirmation.",
            confirmButton: verb
        )
    }
}
