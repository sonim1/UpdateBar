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
            .viewLogs,
            .quit,
        ]

        XCTAssertTrue(actions.allSatisfy { model.section(for: $0) == nil })
    }

    func testSectionsExposeStableOrderTitlesAndSymbols() {
        XCTAssertEqual(
            DashboardSection.allCases,
            [.overview, .items, .scan, .settings, .about]
        )
        XCTAssertEqual(DashboardSection.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
        XCTAssertEqual(
            DashboardSection.allCases.map(\.title),
            ["Overview", "Items", "Scan & Add", "Settings", "About"]
        )
        XCTAssertEqual(
            DashboardSection.allCases.map(\.systemImageName),
            ["chart.bar", "list.bullet", "magnifyingglass", "gearshape", "info.circle"]
        )
    }

    func testSettingsAndAboutActionsMapToSections() {
        let model = DashboardNavigationModel()

        XCTAssertEqual(model.section(for: .openConfig), .settings)
        XCTAssertEqual(model.section(for: .about), .about)
    }
}
