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
            // Outside the 28-day window: ignored.
            update(at: calendar.date(byAdding: .day, value: -28, to: now)!),
            // Failed updates are not chart-worthy.
            HistoryEvent(event: .updateFinished, id: "x", outcome: "failed", at: now),
        ]

        let summary = DashboardModel(calendar: calendar).summary(
            snapshot: snapshot(outdated: 0, untrusted: 0), events: events, now: now)

        XCTAssertEqual(summary.updatesPerDay.count, 28)
        XCTAssertEqual(summary.updatesPerDay.first?.count, 1)
        XCTAssertEqual(summary.updatesPerDay.last?.count, 2)
        XCTAssertEqual(summary.updatesPerDay[26].count, 1)
        XCTAssertEqual(summary.updatesPerDay.map(\.count).reduce(0, +), 4)
        let days = summary.updatesPerDay.map(\.day)
        XCTAssertEqual(days, days.sorted())
    }

    func testEmptyHistoryYieldsZeroBucketsAndNilLastUpdated() {
        let summary = DashboardModel(calendar: calendar).summary(
            snapshot: snapshot(outdated: 1, untrusted: 0), events: [], now: now)

        XCTAssertNil(summary.lastUpdated)
        XCTAssertEqual(summary.updatesPerDay.count, 28)
        XCTAssertTrue(summary.updatesPerDay.allSatisfy { $0.count == 0 })
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
}
