import UpdateBarMenuBar
import XCTest

final class DashboardNavigationModelTests: XCTestCase {
    func testDefaultsToOverview() {
        XCTAssertEqual(DashboardNavigationModel().selectedSection, .overview)
    }

    func testSelectingSectionUpdatesSelection() {
        var model = DashboardNavigationModel()

        model.select(.scan)

        XCTAssertEqual(model.selectedSection, .scan)
    }

    func testDashboardActionsMapToTheirSections() {
        let model = DashboardNavigationModel()

        XCTAssertEqual(model.section(for: .overview), .overview)
        XCTAssertEqual(model.section(for: .manageItems), .items)
        XCTAssertEqual(model.section(for: .scanAndAdd), .scan)
    }

    func testNonDashboardActionsDoNotMapToSections() {
        let model = DashboardNavigationModel()
        let actions: [MenuBarMenuAction] = [
            .refreshStatus,
            .checkNow,
            .updateAllApprovedOutdated,
            .openTUI,
            .openConfig,
            .viewLogs,
            .quit,
        ]

        XCTAssertTrue(actions.allSatisfy { model.section(for: $0) == nil })
    }

    func testSectionsExposeStableOrderTitlesAndSymbols() {
        XCTAssertEqual(DashboardSection.allCases, [.overview, .items, .scan])
        XCTAssertEqual(DashboardSection.allCases.map(\.rawValue), [0, 1, 2])
        XCTAssertEqual(DashboardSection.allCases.map(\.title), ["Overview", "Items", "Scan & Add"])
        XCTAssertEqual(
            DashboardSection.allCases.map(\.systemImageName),
            ["chart.bar", "list.bullet", "magnifyingglass"]
        )
    }
}
