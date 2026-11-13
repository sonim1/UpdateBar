import Foundation
import UpdateBarCore

public final class MenuBarDailyScheduler {
    private let defaults: UserDefaults
    private let storageKey: String
    private let startedAt: Date

    public init(defaults: UserDefaults, storageKey: String, now: Date = Date()) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.startedAt = now
    }

    public func claimDueRun(
        _ schedule: ScheduleConfig,
        now: Date = Date(),
        calendar: Calendar = .current,
        isBusy: Bool = false
    ) -> ScheduleMode? {
        guard !isBusy, schedule.mode != .off,
            let components = ScheduleConfig.components(for: schedule.time)
        else { return nil }
        let lastAttempt = defaults.object(forKey: storageKey) as? Date
        if let lastAttempt,
            lastAttempt > now || calendar.isDate(lastAttempt, inSameDayAs: now)
        {
            return nil
        }

        let today = calendar.startOfDay(for: now)
        guard
            let todayRun = calendar.nextDate(
                after: today.addingTimeInterval(-1), matching: components,
                matchingPolicy: .nextTime, repeatedTimePolicy: .first
            )
        else { return nil }
        let due: Date
        if todayRun <= now {
            due = todayRun
        } else {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                let previousRun = calendar.nextDate(
                    after: yesterday.addingTimeInterval(-1), matching: components,
                    matchingPolicy: .nextTime, repeatedTimePolicy: .first
                )
            else { return nil }
            due = previousRun
        }
        let baseline = lastAttempt ?? calendar.startOfDay(for: startedAt)
        guard due >= baseline, lastAttempt == nil || due > baseline else { return nil }
        // Claim before starting: failed or interrupted work must not repeat every tick.
        defaults.set(now, forKey: storageKey)
        return schedule.mode
    }
}
