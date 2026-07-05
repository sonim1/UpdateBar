public enum MenuBarMenuAction: Equatable, Sendable {
    case refreshStatus
    case checkNow
    case updateAllApprovedOutdated
    case openTUI
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
        .openConfig,
        .viewLogs,
        .quit,
    ]

    public static let errorRecovery: [MenuBarMenuAction] = [
        .refreshStatus,
        .checkNow,
        .openTUI,
        .openConfig,
        .viewLogs,
        .quit,
    ]
}
