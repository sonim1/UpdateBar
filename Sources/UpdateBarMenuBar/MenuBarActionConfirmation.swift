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

    public static func updateItem(id: String) -> MenuBarActionConfirmation {
        MenuBarActionConfirmation(
            title: "Update \(id)?",
            message: "This runs the update command for \(id).",
            toolTip: "Runs \(id) after confirmation.",
            confirmButton: "Update"
        )
    }
}
