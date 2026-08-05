public enum DashboardSection: Int, CaseIterable, Equatable, Sendable {
    case overview
    case items
    case scan
    case logs
    case settings
    case about

    public var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .items:
            return "Items"
        case .scan:
            return "Scan & Add"
        case .logs:
            return "Logs"
        case .settings:
            return "Settings"
        case .about:
            return "About"
        }
    }

    public var systemImageName: String {
        switch self {
        case .overview:
            return "chart.bar"
        case .items:
            return "list.bullet"
        case .scan:
            return "magnifyingglass"
        case .logs:
            return "doc.text"
        case .settings:
            return "gearshape"
        case .about:
            return "info.circle"
        }
    }
}

public struct DashboardNavigationModel: Equatable, Sendable {
    public private(set) var selectedSection: DashboardSection

    public init(selectedSection: DashboardSection = .overview) {
        self.selectedSection = selectedSection
    }

    public mutating func select(_ section: DashboardSection) {
        selectedSection = section
    }

    public func section(for action: MenuBarMenuAction) -> DashboardSection? {
        switch action {
        case .overview:
            return .overview
        case .manageItems:
            return .items
        case .scanAndAdd:
            return .scan
        case .viewLogs:
            return .logs
        case .openConfig:
            return .settings
        case .about:
            return .about
        case .refreshStatus, .checkNow, .updateAllApprovedOutdated, .openTUI,
            .checkForUpdates, .quit:
            return nil
        }
    }
}
