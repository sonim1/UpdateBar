import Foundation
import UpdateBarCore

public struct DashboardDayCount: Equatable, Sendable {
    public var day: Date
    public var count: Int

    public init(day: Date, count: Int) {
        self.day = day
        self.count = count
    }
}

public struct DashboardSummary: Equatable, Sendable {
    public var pendingUpdates: Int
    public var approvalsWaiting: Int
    public var lastChecked: Date?
    public var lastUpdated: Date?
    /// One bucket per day, oldest first, covering the requested window.
    public var updatesPerDay: [DashboardDayCount]

    public init(
        pendingUpdates: Int,
        approvalsWaiting: Int,
        lastChecked: Date?,
        lastUpdated: Date?,
        updatesPerDay: [DashboardDayCount]
    ) {
        self.pendingUpdates = pendingUpdates
        self.approvalsWaiting = approvalsWaiting
        self.lastChecked = lastChecked
        self.lastUpdated = lastUpdated
        self.updatesPerDay = updatesPerDay
    }
}

public struct DashboardModel: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func summary(
        snapshot: StatusSnapshot,
        events: [HistoryEvent],
        now: Date,
        days: Int = 28
    ) -> DashboardSummary {
        let successfulUpdates = events.filter {
            $0.event == .updateFinished && $0.outcome == "updated"
        }
        return DashboardSummary(
            pendingUpdates: snapshot.summary.outdated,
            approvalsWaiting: snapshot.summary.untrusted,
            lastChecked: snapshot.items.compactMap(\.lastChecked).max()
                ?? snapshot.generatedAt,
            lastUpdated: successfulUpdates.map(\.at).max(),
            updatesPerDay: buckets(for: successfulUpdates, now: now, days: days)
        )
    }

    private func buckets(
        for events: [HistoryEvent],
        now: Date,
        days: Int
    ) -> [DashboardDayCount] {
        let today = calendar.startOfDay(for: now)
        guard days > 0,
            let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today)
        else { return [] }
        var counts: [Date: Int] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.at)
            guard day >= windowStart, day <= today else { continue }
            counts[day, default: 0] += 1
        }
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: windowStart)
            else { return nil }
            return DashboardDayCount(day: day, count: counts[day] ?? 0)
        }
    }
}
