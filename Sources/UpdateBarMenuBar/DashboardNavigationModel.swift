public enum DashboardSection: Int, CaseIterable, Equatable, Sendable {
    case overview
    case items
    case scan

    public var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .items:
            return "Items"
        case .scan:
            return "Scan & Add"
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
        case .refreshStatus, .checkNow, .updateAllApprovedOutdated, .openTUI, .openConfig,
            .viewLogs, .quit:
            return nil
        }
    }
}
