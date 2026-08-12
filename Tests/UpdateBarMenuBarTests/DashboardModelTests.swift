import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class DashboardModelTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    // 2026-07-10T12:00:00Z
    private let now = Date(timeIntervalSince1970: 1_783_080_000)

    func testSummarizesTilesFromSnapshotAndHistory() {
        let snapshot = snapshot(outdated: 3, untrusted: 2)
        let lastUpdate = now.addingTimeInterval(-3_600)
        let events = [
            update(at: now.addingTimeInterval(-7_200)),
            update(at: lastUpdate),
            HistoryEvent(event: .checkFinished, outdated: 3, at: now),
            HistoryEvent(
                event: .updateFinished, id: "x", outcome: "failed",
                at: now.addingTimeInterval(-60)),
        ]

        let summary = DashboardModel(calendar: calendar).summary(
            snapshot: snapshot, events: events, now: now)

        XCTAssertEqual(summary.pendingUpdates, 3)
        XCTAssertEqual(summary.approvalsWaiting, 2)
        XCTAssertEqual(summary.lastUpdated, lastUpdate)
        XCTAssertEqual(summary.lastChecked, snapshot.generatedAt)
    }

    func testBucketsSuccessfulUpdatesPerDayOldestFirst() {
        let events = [
            update(at: now),
            update(at: now.addingTimeInterval(-60)),
            update(at: calendar.date(byAdding: .day, value: -1, to: now)!),
            update(at: calendar.date(byAdding: .day, value: -27, to: now)!),
            // Included in the 30-day window.
            update(at: calendar.date(byAdding: .day, value: -28, to: now)!),
            // The oldest day in the 30-day range is -29.
            update(at: calendar.date(byAdding: .day, value: -29, to: now)!),
            // One day outside the range is excluded.
            update(at: calendar.date(byAdding: .day, value: -30, to: now)!),
            // Failed updates are not chart-worthy.
            HistoryEvent(event: .updateFinished, id: "x", outcome: "failed", at: now),
        ]

        let summary = DashboardModel(calendar: calendar).summary(
            snapshot: snapshot(outdated: 0, untrusted: 0), events: events, now: now)

        XCTAssertEqual(summary.updatesPerDay.count, 30)
        XCTAssertEqual(summary.updatesPerDay.first?.count, 1)
        XCTAssertEqual(summary.updatesPerDay[1].count, 1)
        XCTAssertEqual(summary.updatesPerDay[2].count, 1)
        XCTAssertEqual(summary.updatesPerDay[3].count, 0)
        XCTAssertEqual(summary.updatesPerDay.last?.count, 2)
        XCTAssertEqual(summary.updatesPerDay[28].count, 1)
        XCTAssertEqual(summary.updatesPerDay.map(\.count).reduce(0, +), 6)
        let days = summary.updatesPerDay.map(\.day)
        XCTAssertEqual(days, days.sorted())
    }

    func testEmptyHistoryYieldsZeroBucketsAndNilLastUpdated() {
        let summary = DashboardModel(calendar: calendar).summary(
            snapshot: snapshot(outdated: 1, untrusted: 0), events: [], now: now)

        XCTAssertNil(summary.lastUpdated)
        XCTAssertEqual(summary.updatesPerDay.count, 30)
        XCTAssertTrue(summary.updatesPerDay.allSatisfy { $0.count == 0 })
    }

    func testHistoryLoadUsesEmptyBucketsWhenHistoryFails() {
        let history = MenuBarUpdateHistory.load(
            snapshot: snapshot(outdated: 2, untrusted: 1),
            loadEvents: { throw HistoryLoadError.unavailable },
            dashboardModel: DashboardModel(calendar: calendar),
            now: now
        )

        XCTAssertEqual(history.buckets.count, 30)
        XCTAssertEqual(history.totalUpdates, 0)
    }

    private func update(at date: Date) -> HistoryEvent {
        HistoryEvent(event: .updateFinished, id: "tool", outcome: "updated", at: date)
    }

    private func snapshot(outdated: Int, untrusted: Int) -> StatusSnapshot {
        let json = """
            {
              "generated_at": "2026-07-10T12:00:00Z",
              "summary": {
                "total": \(outdated + untrusted),
                "outdated": \(outdated),
                "errors": 0,
                "untrusted": \(untrusted),
                "pinned": 0,
                "disabled": 0,
                "checking": 0,
                "differs": 0
              },
              "items": []
            }
            """
        return try! JSONDecoder.updateBar.decode(StatusSnapshot.self, from: Data(json.utf8))
    }

    private enum HistoryLoadError: Error {
        case unavailable
    }
}
