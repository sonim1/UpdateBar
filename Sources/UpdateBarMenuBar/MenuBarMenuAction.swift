public enum MenuBarMenuAction: Equatable, Sendable {
    case refreshStatus
    case checkNow
    case updateAllApprovedOutdated
    case openTUI
    case overview
    case manageItems
    case scanAndAdd
    case openConfig
    case viewLogs
    case checkForUpdates
    case quit

    public var title: String {
        switch self {
        case .refreshStatus:
            return "Refresh Status"
        case .checkNow:
            return "Check Now"
        case .updateAllApprovedOutdated:
            return "Update All"
        case .openTUI:
            return "Open TUI"
        case .overview:
            return "Dashboard"
        case .manageItems:
            return "Manage Items..."
        case .scanAndAdd:
            return "Scan & Add"
        case .openConfig:
            return "Open Config"
        case .viewLogs:
            return "View Logs"
        case .checkForUpdates:
            return "Check for Updates..."
        case .quit:
            return "Quit"
        }
    }

    public static let footer: [MenuBarMenuAction] = [
        .openTUI,
        .overview,
        .manageItems,
        .scanAndAdd,
        .openConfig,
        .viewLogs,
        .checkForUpdates,
        .quit,
    ]

    public static let errorRecovery: [MenuBarMenuAction] = [
        .refreshStatus,
        .checkNow,
        .openTUI,
        .overview,
        .manageItems,
        .scanAndAdd,
        .openConfig,
        .viewLogs,
        .checkForUpdates,
        .quit,
    ]
}
