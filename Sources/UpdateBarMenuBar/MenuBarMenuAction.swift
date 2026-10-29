public enum MenuBarMenuAction: Equatable, Sendable {
    case refreshStatus
    case checkNow
    case updateAllApprovedOutdated
    case openTUI
    case overview
    case manageItems
    case scanAndAdd
    case openConfig
    case about
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
            return "Settings..."
        case .about:
            return "About UpdateBar"
        case .viewLogs:
            return "View Logs"
        case .checkForUpdates:
            return "Check for Updates..."
        case .quit:
            return "Quit"
        }
    }

    public var systemSymbolName: String {
        switch self {
        case .refreshStatus: "arrow.clockwise"
        case .checkNow: "magnifyingglass"
        case .updateAllApprovedOutdated: "arrow.down.circle"
        case .openTUI: "terminal"
        case .overview: "square.grid.2x2"
        case .manageItems: "list.bullet"
        case .scanAndAdd: "plus.magnifyingglass"
        case .openConfig: "gearshape"
        case .about: "info.circle"
        case .viewLogs: "doc.text"
        case .checkForUpdates: "arrow.triangle.2.circlepath"
        case .quit: "power"
        }
    }

    public static let footer: [MenuBarMenuAction] = [
        .overview,
        .checkForUpdates,
        .quit,
    ]

    public static let more: [MenuBarMenuAction] = [
        .manageItems,
        .scanAndAdd,
        .openConfig,
        .about,
    ]

    public static let errorRecovery: [MenuBarMenuAction] = [
        .refreshStatus,
        .checkNow,
        .overview,
        .checkForUpdates,
        .quit,
    ]
}
