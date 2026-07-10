public enum MenuBarMenuAction: Equatable, Sendable {
    case refreshStatus
    case checkNow
    case updateAllApprovedOutdated
    case openTUI
    case manageItems
    case scanAndAdd
    case openConfig
    case viewLogs
    case quit

    public var title: String {
        switch self {
        case .refreshStatus:
            return "Refresh Status"
        case .checkNow:
            return "Check Now"
        case .updateAllApprovedOutdated:
            return "Run Updates"
        case .openTUI:
            return "Open TUI"
        case .manageItems:
            return "Manage Items..."
        case .scanAndAdd:
            return "Scan & Add"
        case .openConfig:
            return "Open Config"
        case .viewLogs:
            return "View Logs"
        case .quit:
            return "Quit"
        }
    }

    public static let footer: [MenuBarMenuAction] = [
        .openTUI,
        .manageItems,
        .scanAndAdd,
        .openConfig,
        .viewLogs,
        .quit,
    ]

    public static let errorRecovery: [MenuBarMenuAction] = [
        .refreshStatus,
        .checkNow,
        .openTUI,
        .manageItems,
        .scanAndAdd,
        .openConfig,
        .viewLogs,
        .quit,
    ]
}
