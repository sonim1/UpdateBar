import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class MenuBarDailySchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    func testWaitsUntilDailyTimeAndPersistsClaimAcrossRestart() throws {
        let suite = "updatebar-schedule-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scheduler = MenuBarDailyScheduler(
            defaults: defaults, storageKey: "run", now: date(12, 8))
        XCTAssertNil(scheduler.claimDueRun(.default, now: date(12, 8), calendar: calendar))
        XCTAssertEqual(
            scheduler.claimDueRun(.default, now: date(12, 9), calendar: calendar), .check)
        let restarted = MenuBarDailyScheduler(
            defaults: defaults, storageKey: "run", now: date(12, 10))
        XCTAssertNil(restarted.claimDueRun(.default, now: date(12, 18), calendar: calendar))
        XCTAssertNil(restarted.claimDueRun(.default, now: date(13, 8), calendar: calendar))
        XCTAssertEqual(
            restarted.claimDueRun(.default, now: date(13, 9), calendar: calendar), .check)
    }

    func testCatchesUpOnceAfterSleepAndDefersWhileBusy() throws {
        let suite = "updatebar-schedule-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scheduler = MenuBarDailyScheduler(
            defaults: defaults, storageKey: "run", now: date(12, 8))
        XCTAssertNil(
            scheduler.claimDueRun(.default, now: date(12, 10), calendar: calendar, isBusy: true))
        XCTAssertEqual(
            scheduler.claimDueRun(.default, now: date(14, 8), calendar: calendar), .check)
        XCTAssertNil(scheduler.claimDueRun(.default, now: date(14, 9), calendar: calendar))
    }

    func testOffAndTimeEditsDoNotCauseDuplicateDailyRuns() throws {
        let suite = "updatebar-schedule-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scheduler = MenuBarDailyScheduler(
            defaults: defaults, storageKey: "run", now: date(12, 8))
        XCTAssertNil(
            scheduler.claimDueRun(
                ScheduleConfig(mode: .off, time: "09:00"), now: date(12, 10), calendar: calendar))
        XCTAssertEqual(
            scheduler.claimDueRun(
                ScheduleConfig(mode: .checkAndUpdate, time: "10:00"), now: date(12, 10),
                calendar: calendar), .checkAndUpdate)
        XCTAssertNil(
            scheduler.claimDueRun(
                ScheduleConfig(mode: .checkAndUpdate, time: "11:00"), now: date(12, 12),
                calendar: calendar))
        XCTAssertNil(scheduler.claimDueRun(.default, now: date(11, 12), calendar: calendar))
    }

    func testSpringForwardRunsAtNextValidTime() throws {
        let suite = "updatebar-schedule-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let morning = calendar.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 1))!
        let afterJump = calendar.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 3))!
        let scheduler = MenuBarDailyScheduler(defaults: defaults, storageKey: "run", now: morning)
        let schedule = ScheduleConfig(mode: .check, time: "02:30")
        XCTAssertNil(scheduler.claimDueRun(schedule, now: morning, calendar: calendar))
        XCTAssertEqual(scheduler.claimDueRun(schedule, now: afterJump, calendar: calendar), .check)
        XCTAssertNil(
            scheduler.claimDueRun(
                schedule, now: afterJump.addingTimeInterval(3600), calendar: calendar))
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    func testRepeatedFallBackHourAndNewHomeAreIndependent() throws {
        let suite = "updatebar-schedule-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = calendar.date(from: DateComponents(year: 2027, month: 11, day: 7))!
        let first = calendar.nextDate(
            after: start, matching: DateComponents(hour: 1, minute: 30), matchingPolicy: .nextTime,
            repeatedTimePolicy: .first)!
        let second = calendar.nextDate(
            after: start, matching: DateComponents(hour: 1, minute: 30), matchingPolicy: .nextTime,
            repeatedTimePolicy: .last)!
        let scheduler = MenuBarDailyScheduler(defaults: defaults, storageKey: "home-a", now: start)
        let schedule = ScheduleConfig(mode: .check, time: "01:30")
        XCTAssertEqual(scheduler.claimDueRun(schedule, now: first, calendar: calendar), .check)
        XCTAssertNil(scheduler.claimDueRun(schedule, now: second, calendar: calendar))
        let otherHome = MenuBarDailyScheduler(defaults: defaults, storageKey: "home-b", now: start)
        XCTAssertEqual(otherHome.claimDueRun(schedule, now: second, calendar: calendar), .check)
    }
}
