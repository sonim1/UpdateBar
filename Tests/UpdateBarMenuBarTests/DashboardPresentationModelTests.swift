import Foundation
import XCTest

@testable import UpdateBarMenuBar

final class DashboardPresentationModelTests: XCTestCase {
    private let model = DashboardPresentationModel(
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(secondsFromGMT: 0)!
    )

    func testOverviewCountsKeepTitlesOutOfVisibleValuesAndMeaningInHelp() throws {
        let metrics = model.overviewMetrics(for: summary())
        let updates = try metric(labeled: "Updates", in: metrics)
        let approvals = try metric(labeled: "Awaiting Approval", in: metrics)

        XCTAssertEqual(updates.iconName, "arrow.down.circle")
        XCTAssertEqual(updates.visibleValue, "4")
        XCTAssertEqual(updates.help, "Updates: 4 available.")
        XCTAssertEqual(updates.accessibilityValue, "4 available")

        XCTAssertEqual(approvals.iconName, "hourglass")
        XCTAssertEqual(approvals.visibleValue, "2")
        XCTAssertEqual(approvals.help, "Awaiting Approval: 2 items.")
        XCTAssertEqual(approvals.accessibilityValue, "2 items")

        for metric in [updates, approvals] {
            XCTAssertFalse(metric.visibleValue.contains(metric.accessibilityLabel))
        }
    }

    func testAwaitingApprovalUsesSingularItemMeaning() throws {
        var value = summary()
        value.approvalsWaiting = 1

        let approvals = try metric(
            labeled: "Awaiting Approval",
            in: model.overviewMetrics(for: value)
        )

        XCTAssertEqual(approvals.visibleValue, "1")
        XCTAssertEqual(approvals.help, "Awaiting Approval: 1 item.")
        XCTAssertEqual(approvals.accessibilityValue, "1 item")
    }

    func testOverviewDatesUseCompactValuesAndUnabridgedHelp() throws {
        let metrics = model.overviewMetrics(for: summary())
        let checked = try metric(labeled: "Last Checked", in: metrics)
        let updated = try metric(labeled: "Last Updated", in: metrics)

        XCTAssertEqual(checked.iconName, "magnifyingglass")
        XCTAssertTrue(checked.visibleValue.contains("Jan 2"))
        XCTAssertTrue(checked.visibleValue.contains("3:04"))
        XCTAssertFalse(checked.visibleValue.contains("Last Checked"))
        XCTAssertFalse(checked.visibleValue.contains("Tuesday"))
        XCTAssertTrue(checked.help.contains("Tuesday, January 2, 2024"))
        XCTAssertTrue(checked.accessibilityValue.contains("Tuesday, January 2, 2024"))

        XCTAssertEqual(updated.iconName, "clock")
        XCTAssertTrue(updated.visibleValue.contains("Jan 3"))
        XCTAssertTrue(updated.help.contains("Wednesday, January 3, 2024"))
        XCTAssertTrue(updated.accessibilityValue.contains("Wednesday, January 3, 2024"))
    }

    func testMissingOverviewDatesUseDashAndMeaningfulHelp() throws {
        let metrics = model.overviewMetrics(
            for: summary(lastChecked: nil, lastUpdated: nil)
        )
        let checked = try metric(labeled: "Last Checked", in: metrics)
        let updated = try metric(labeled: "Last Updated", in: metrics)

        XCTAssertEqual(checked.visibleValue, "–")
        XCTAssertEqual(checked.help, "Last Checked: Not available.")
        XCTAssertEqual(checked.accessibilityValue, "Not available")
        XCTAssertEqual(updated.visibleValue, "–")
        XCTAssertEqual(updated.help, "Last Updated: Not available.")
        XCTAssertEqual(updated.accessibilityValue, "Not available")
    }

    func testScanCountsShowIntegersWhileHelpKeepsFullMeaning() {
        let counts = model.scanCounts(discovered: 7, enabled: 5, disabled: 2)

        XCTAssertEqual(counts.map(\.visibleValue), ["7", "5", "2"])
        XCTAssertEqual(counts.map(\.accessibilityLabel), ["Discovered", "Enabled", "Disabled"])
        XCTAssertEqual(
            counts.map(\.help),
            [
                "Discovered: 7. Tools found by the most recent manual scan.",
                "Enabled: 5. Discovered registered tools that are enabled.",
                "Disabled: 2. Unchecked registered tools are disabled, not deleted.",
            ]
        )
        for count in counts {
            XCTAssertFalse(count.visibleValue.contains(count.accessibilityLabel))
        }
    }

    func testReusableHelpStringsKeepExactRefreshAndTrackingMeaning() {
        XCTAssertEqual(DashboardPresentationModel.itemsRefreshHelp, "Refresh items")
        XCTAssertEqual(
            DashboardPresentationModel.scanTrackingHelp,
            "Unchecked registered tools are disabled, not deleted."
        )
    }

    func testScanControlFailurePresentationIsCompactAndRetryClearsFailureMarker() {
        let failed = model.scanControl(state: .failed)
        let retrying = model.scanControl(state: .scanning)

        XCTAssertEqual(failed.iconName, "exclamationmark.triangle.fill")
        XCTAssertEqual(failed.toolTip, "Scan failed. Try again.")
        XCTAssertEqual(failed.accessibilityLabel, "Scan failed. Scan again")
        XCTAssertNil(retrying.iconName)
        XCTAssertEqual(retrying.toolTip, "Scanning for installed tools")
        XCTAssertEqual(retrying.accessibilityLabel, "Scanning for installed tools")
    }

    func testScanRowActionLabelReflectsCurrentCheckedState() {
        XCTAssertEqual(
            model.scanRowActionLabel(candidateName: "Example Tool", isChecked: true),
            "Disable Example Tool"
        )
        XCTAssertEqual(
            model.scanRowActionLabel(candidateName: "Example Tool", isChecked: false),
            "Enable Example Tool"
        )
    }

    func testScanMutationFailureAnnouncementDescribesRedactedRollback() {
        let announcement = model.scanMutationFailureAnnouncement(
            candidateName: "Example Tool",
            restoredState: .enabled,
            message: "token sk-or-v1-secret-value"
        )

        XCTAssertTrue(announcement.contains("Update failed for Example Tool."))
        XCTAssertTrue(announcement.contains("Restored Enabled."))
        XCTAssertTrue(announcement.contains("[REDACTED]"))
        XCTAssertFalse(announcement.contains("sk-or-v1-secret-value"))
    }

    private func metric(
        labeled label: String,
        in metrics: [DashboardMetricPresentation]
    ) throws -> DashboardMetricPresentation {
        try XCTUnwrap(metrics.first { $0.accessibilityLabel == label })
    }

    private func summary(
        lastChecked: Date? = Date(timeIntervalSince1970: 1_704_164_645),
        lastUpdated: Date? = Date(timeIntervalSince1970: 1_704_251_045)
    ) -> DashboardSummary {
        DashboardSummary(
            pendingUpdates: 4,
            approvalsWaiting: 2,
            lastChecked: lastChecked,
            lastUpdated: lastUpdated,
            updatesPerDay: []
        )
    }
}
