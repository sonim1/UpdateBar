#if os(macOS)
    import AppKit
    import UpdateBarMenuBar
    import XCTest

    @testable import UpdateBarMenuBarApp

    @MainActor
    final class MenuBarUpdateHistoryViewTests: XCTestCase {
        func testAccessibilitySummaryIncludesDailySeriesAndSingularCopy() {
            let history = MenuBarUpdateHistory(
                buckets: [
                    DashboardDayCount(day: .distantPast, count: 1),
                    DashboardDayCount(day: .now, count: 0),
                ]
            )
            let view = MenuBarUpdateHistoryView(history: history)

            XCTAssertEqual(view.accessibilityRole(), .group)
            XCTAssertEqual(
                view.accessibilityValue() as? String,
                "1 update. Daily counts: 1, 0."
            )
        }

        func testBarHeightsScaleToTheLargestDailyCount() {
            XCTAssertEqual(
                MenuBarUpdateHistoryView.barHeights(for: [0, 2, 4]),
                [2, 13, 26]
            )
        }
    }
#endif
