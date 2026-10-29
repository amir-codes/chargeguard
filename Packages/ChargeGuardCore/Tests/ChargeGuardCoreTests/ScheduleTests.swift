import XCTest
@testable import ChargeGuardCore

final class ScheduleTests: XCTestCase {
    let calendar = utcCalendar()

    /// 2027-01-04 is a Monday (weekday 2).
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    func rule(weekdays: Set<Int> = [], hour: Int = 9, minute: Int = 0, action: ScheduleAction = .topUp,
              repeats: ScheduleRepeat = .weekly) -> ScheduleRule {
        ScheduleRule(weekdays: weekdays, hour: hour, minute: minute, action: action, repeats: repeats,
                     createdAt: date(1, 0))
    }

    func testRunsAtTheScheduledTime() {
        let r = rule()
        XCTAssertTrue(ScheduleEngine.check(rules: [r], lastCheck: date(4, 8, 59), now: date(4, 8, 59), calendar: calendar).due.isEmpty)
        let result = ScheduleEngine.check(rules: [r], lastCheck: date(4, 8, 59), now: date(4, 9, 0), calendar: calendar)
        XCTAssertEqual(result.due.map(\.scheduledAt), [date(4, 9)])
        XCTAssertEqual(result.updatedRules[0].lastRun, date(4, 9))
        // Does not fire twice.
        let again = ScheduleEngine.check(rules: result.updatedRules, lastCheck: date(4, 9), now: date(4, 9, 5), calendar: calendar)
        XCTAssertTrue(again.due.isEmpty)
    }

    func testWeekdayFilter() {
        let monday = rule(weekdays: [2])
        XCTAssertEqual(ScheduleEngine.check(rules: [monday], lastCheck: date(4, 8), now: date(4, 10), calendar: calendar).due.count, 1)
        XCTAssertEqual(ScheduleEngine.check(rules: [monday], lastCheck: date(5, 8), now: date(5, 10), calendar: calendar).due.count, 0)
    }

    func testCatchUpWithinTwoHoursAfterWakeOrBoot() {
        let r = rule()
        // Asleep from 08:00 to 10:30: the 09:00 run is 90 minutes late and still runs.
        let result = ScheduleEngine.check(rules: [r], lastCheck: date(4, 8), now: date(4, 10, 30), calendar: calendar)
        XCTAssertEqual(result.due.count, 1)
        XCTAssertTrue(result.missed.isEmpty)
    }

    func testMissedAfterTwoHours() {
        let r = rule()
        let result = ScheduleEngine.check(rules: [r], lastCheck: date(4, 8), now: date(4, 11, 1), calendar: calendar)
        XCTAssertTrue(result.due.isEmpty)
        XCTAssertEqual(result.missed.count, 1)
        // A missed run is recorded so it is not reported again.
        let again = ScheduleEngine.check(rules: result.updatedRules, lastCheck: date(4, 11, 1), now: date(4, 11, 2), calendar: calendar)
        XCTAssertTrue(again.missed.isEmpty)
    }

    func testOnceRuleDisablesItself() {
        let r = rule(repeats: .once)
        let result = ScheduleEngine.check(rules: [r], lastCheck: date(4, 8), now: date(4, 9), calendar: calendar)
        XCTAssertEqual(result.due.count, 1)
        XCTAssertFalse(result.updatedRules[0].enabled)
        XCTAssertNil(ScheduleEngine.nextRun(of: result.updatedRules[0], after: date(4, 9), calendar: calendar))
    }

    func testDisabledRuleNeverRuns() {
        var r = rule()
        r.enabled = false
        XCTAssertTrue(ScheduleEngine.check(rules: [r], lastCheck: date(4, 8), now: date(4, 10), calendar: calendar).due.isEmpty)
    }

    func testRuleCreatedAfterTimeDoesNotFireRetroactively() {
        var r = rule()
        r.createdAt = date(4, 9, 30)
        XCTAssertTrue(ScheduleEngine.check(rules: [r], lastCheck: nil, now: date(4, 10), calendar: calendar).due.isEmpty)
    }

    func testNextRun() {
        let r = rule(weekdays: [2, 4], hour: 7, minute: 30) // Monday and Wednesday
        XCTAssertEqual(ScheduleEngine.nextRun(of: r, after: date(4, 8), calendar: calendar), date(6, 7, 30))
        XCTAssertEqual(ScheduleEngine.nextRun(of: r, after: date(4, 7), calendar: calendar), date(4, 7, 30))
        let soonest = ScheduleEngine.nextRun(rules: [r, rule(hour: 12)], after: date(4, 8), calendar: calendar)
        XCTAssertEqual(soonest?.date, date(4, 12))
    }

    func testControllerRunsScheduleAndCatchesUp() {
        let clock = ManualTimeSource(date(4, 8, 55))
        let sim = SimHarness(charge: 80, clock: clock)
        var r = rule(action: .setLimit(65))
        r.createdAt = date(4, 0)
        _ = sim.command(.setSchedule([r]))
        // Simulate sleep: no ticks until 09:40.
        clock.set(date(4, 9, 40))
        sim.controller.systemDidWake()
        sim.controller.tickSync()
        XCTAssertEqual(sim.status.config.chargeLimit, 65)
        XCTAssertTrue(sim.events.contains { if case .scheduleRan = $0.event { return true } else { return false } })
        XCTAssertNotNil(sim.status.nextScheduledRun)
    }

    func testScheduledCalibrationStarts() {
        let clock = ManualTimeSource(date(4, 8, 59))
        let sim = SimHarness(charge: 70, clock: clock)
        var r = rule(action: .startCalibration)
        r.createdAt = date(4, 0)
        _ = sim.command(.setSchedule([r]))
        sim.tick(65)
        XCTAssertEqual(sim.status.control.calibration?.origin, "schedule")
    }
}
