import Foundation
import Testing
@testable import WakeUp

struct SchedulePlannerTests {
    // Los Angeles still changes its clocks (Mar 8 and Nov 1, 2026); BC is
    // moving to permanent daylight time, so Vancouver can't test fall-back.
    private func calendar(_ zone: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, zone: String = "America/Los_Angeles") -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func spec(
        hour: Int = 7, minute: Int = 0, weekdays: Set<Int> = .everyDay,
        skipped: [Date] = [], length: Int = 3, enabled: Bool = true
    ) -> AlarmSpec {
        AlarmSpec(
            id: UUID(), hour: hour, minute: minute, weekdays: weekdays, missionID: nil,
            chainLength: length, chainInterval: 180, followUpDelay: 720, isEnabled: enabled, skippedDays: skipped
        )
    }

    // 2026-11-05 is a Thursday.

    @Test func everyDayAlarmRingsToday_IfStillAhead() {
        let now = date(2026, 11, 5, 6, 0)
        let list = SchedulePlanner.occurrences(of: spec(), after: now, days: 3, calendar: calendar())
        #expect(list.map(\.start) == [date(2026, 11, 5, 7), date(2026, 11, 6, 7), date(2026, 11, 7, 7)])
    }

    @Test func alarmThatAlreadyRangTodayStartsTomorrow() {
        let now = date(2026, 11, 5, 8, 0)
        let list = SchedulePlanner.occurrences(of: spec(), after: now, days: 2, calendar: calendar())
        #expect(list.first?.start == date(2026, 11, 6, 7))
    }

    @Test func weekdaysSkipTheWeekend() {
        // Friday evening: the next ring is Monday.
        let now = date(2026, 11, 6, 20, 0)
        let next = SchedulePlanner.nextRing(of: spec(weekdays: .weekdays), after: now, calendar: calendar())
        #expect(next == date(2026, 11, 9, 7))
    }

    @Test func weekWrapsFromSaturdayToSunday() {
        let now = date(2026, 11, 7, 12, 0) // Saturday
        let next = SchedulePlanner.nextRing(of: spec(weekdays: [1]), after: now, calendar: calendar())
        #expect(next == date(2026, 11, 8, 7))
    }

    @Test func singleWeekdayRepeatsWeekly() {
        let now = date(2026, 11, 5, 12, 0) // Thursday, after a Thursday alarm
        let next = SchedulePlanner.nextRing(of: spec(weekdays: [5]), after: now, calendar: calendar())
        #expect(next == date(2026, 11, 12, 7))
    }

    @Test func disabledAlarmHasNoNextRing() {
        #expect(SchedulePlanner.nextRing(of: spec(enabled: false), after: date(2026, 11, 5), calendar: calendar()) == nil)
    }

    @Test func skippedDayIsLeftOut() {
        let skipped = [date(2026, 11, 6)]
        let now = date(2026, 11, 5, 20, 0)
        let next = SchedulePlanner.nextRing(of: spec(skipped: skipped), after: now, calendar: calendar())
        #expect(next == date(2026, 11, 7, 7))
    }

    // MARK: Daylight saving (Vancouver: clocks go forward 2026-03-08, back 2026-11-01)

    @Test func sevenAmStaysSevenAmAcrossSpringForward() {
        let cal = calendar()
        let now = date(2026, 3, 6, 12, 0)
        // March 7 and March 8 (and 9): the clocks jump forward in between.
        let list = SchedulePlanner.occurrences(of: spec(), after: now, days: 4, calendar: cal)
        #expect(list.map { cal.component(.hour, from: $0.start) } == [7, 7, 7])
        // 23 hours apart in real time across the jump.
        #expect(list[1].start.timeIntervalSince(list[0].start) == 23 * 3600)
        #expect(list[2].start.timeIntervalSince(list[1].start) == 24 * 3600)
    }

    @Test func sevenAmStaysSevenAmAcrossFallBack() {
        let cal = calendar()
        let now = date(2026, 10, 30, 12, 0)
        // Oct 31 and Nov 1 (and 2): the clocks go back in between.
        let list = SchedulePlanner.occurrences(of: spec(), after: now, days: 4, calendar: cal)
        #expect(list.map { cal.component(.hour, from: $0.start) } == [7, 7, 7])
        #expect(list[1].start.timeIntervalSince(list[0].start) == 25 * 3600)
    }

    @Test func aTimeThatDoesNotExistMovesForward() {
        let cal = calendar()
        // 2:30 doesn't exist on 2026-03-08 in Vancouver.
        let now = date(2026, 3, 7, 12, 0)
        let list = SchedulePlanner.occurrences(of: spec(hour: 2, minute: 30), after: now, days: 2, calendar: cal)
        let sunday = list.first { cal.component(.day, from: $0.day) == 8 }
        #expect(sunday != nil)
        #expect(cal.component(.hour, from: sunday!.start) == 3)
    }

    @Test func aTimeThatHappensTwiceUsesTheFirst() {
        let cal = calendar()
        // 1:30 happens twice on 2026-11-01 in Vancouver.
        let now = date(2026, 10, 31, 12, 0)
        let list = SchedulePlanner.occurrences(of: spec(hour: 1, minute: 30), after: now, days: 3, calendar: cal)
        let sunday = list.first { cal.component(.day, from: $0.day) == 1 }!
        // First 1:30 is still daylight time (UTC-7), i.e. 08:30 UTC.
        #expect(sunday.start == Date(timeIntervalSince1970: ISO8601DateFormatter().date(from: "2026-11-01T08:30:00Z")!.timeIntervalSince1970))
    }

    // MARK: Time zones

    @Test func sameClockTimeIsADifferentInstantInAnotherZone() {
        let now = Date(timeIntervalSince1970: ISO8601DateFormatter().date(from: "2026-11-05T00:00:00Z")!.timeIntervalSince1970)
        let vancouver = SchedulePlanner.nextRing(of: spec(), after: now, calendar: calendar("America/Los_Angeles"))!
        let toronto = SchedulePlanner.nextRing(of: spec(), after: now, calendar: calendar("America/Toronto"))!
        #expect(toronto.timeIntervalSince(vancouver) == -3 * 3600)
    }

    @Test func changingTimeZoneRebuildsTheChains() {
        let alarm = spec()
        let now = date(2026, 11, 5, 20, 0)
        let vancouver = calendar("America/Los_Angeles")
        let first = SchedulePlanner.plan(specs: [alarm], existing: [], now: now, calendar: vancouver)
        let existing = first.create.map { chain(from: $0) }

        let toronto = calendar("America/Toronto")
        let second = SchedulePlanner.plan(specs: [alarm], existing: existing, now: now, calendar: toronto)
        #expect(second.cancel.count == existing.count)
        #expect(second.create.count == existing.count)
    }

    // MARK: Plan

    private func chain(from planned: PlannedChain, kind: ScheduledChain.Kind = .main) -> ScheduledChain {
        ScheduledChain(
            id: UUID(), alarmID: planned.alarmID, kind: kind, day: planned.day, start: planned.start,
            interval: planned.interval, slotIDs: (0..<planned.count).map { _ in UUID() },
            timeZoneID: planned.timeZoneID, signature: planned.signature
        )
    }

    @Test func plansTheNextFewMornings() {
        let now = date(2026, 11, 5, 20, 0)
        let plan = SchedulePlanner.plan(specs: [spec()], existing: [], now: now, windowDays: 4, calendar: calendar())
        // Today's 7:00 has gone, so tomorrow and the two days after.
        #expect(plan.create.count == 3)
        #expect(plan.create.first?.start == date(2026, 11, 6, 7))
        #expect(plan.cancel.isEmpty)
    }

    @Test func runningTheSamePlanTwiceChangesNothing() {
        let alarm = spec()
        let now = date(2026, 11, 5, 20, 0)
        let cal = calendar()
        let first = SchedulePlanner.plan(specs: [alarm], existing: [], now: now, calendar: cal)
        let existing = first.create.map { chain(from: $0) }
        let second = SchedulePlanner.plan(specs: [alarm], existing: existing, now: now, calendar: cal)
        #expect(second.create.isEmpty)
        #expect(second.cancel.isEmpty)
        #expect(second.expire.isEmpty)
    }

    @Test func editingTheTimeReplacesFutureChains() {
        var alarm = spec()
        let now = date(2026, 11, 5, 20, 0)
        let cal = calendar()
        let existing = SchedulePlanner.plan(specs: [alarm], existing: [], now: now, calendar: cal).create.map { chain(from: $0) }
        alarm.hour = 8
        let plan = SchedulePlanner.plan(specs: [alarm], existing: existing, now: now, calendar: cal)
        #expect(plan.cancel.count == existing.count)
        #expect(plan.create.count == existing.count)
        #expect(plan.create.allSatisfy { cal.component(.hour, from: $0.start) == 8 })
    }

    @Test func disablingOrDeletingCancelsFutureChains() {
        let alarm = spec()
        let now = date(2026, 11, 5, 20, 0)
        let cal = calendar()
        let existing = SchedulePlanner.plan(specs: [alarm], existing: [], now: now, calendar: cal).create.map { chain(from: $0) }

        var disabled = alarm
        disabled.isEnabled = false
        #expect(SchedulePlanner.plan(specs: [disabled], existing: existing, now: now, calendar: cal).cancel.count == existing.count)
        #expect(SchedulePlanner.plan(specs: [], existing: existing, now: now, calendar: cal).cancel.count == existing.count)
    }

    @Test func skippingADayCancelsOnlyThatChain() {
        var alarm = spec()
        let now = date(2026, 11, 5, 20, 0)
        let cal = calendar()
        let existing = SchedulePlanner.plan(specs: [alarm], existing: [], now: now, calendar: cal).create.map { chain(from: $0) }
        alarm.skippedDays = [date(2026, 11, 7)]
        let plan = SchedulePlanner.plan(specs: [alarm], existing: existing, now: now, calendar: cal)
        #expect(plan.cancel.count == 1)
        #expect(plan.cancel.first?.start == date(2026, 11, 7, 7))
        #expect(plan.create.isEmpty)
    }

    @Test func aChainThatIsRingingIsNeverCancelled() {
        var alarm = spec()
        let now = date(2026, 11, 6, 7, 1)
        let cal = calendar()
        let ringing = chain(from: PlannedChain(
            alarmID: alarm.id, day: date(2026, 11, 6), start: date(2026, 11, 6, 7), count: 3, interval: 180,
            timeZoneID: cal.timeZone.identifier, signature: SchedulePlanner.signature(of: alarm, calendar: cal)
        ))
        alarm.isEnabled = false
        let plan = SchedulePlanner.plan(specs: [alarm], existing: [ringing], now: now, calendar: cal)
        #expect(plan.cancel.isEmpty)
        #expect(plan.expire.isEmpty)
    }

    @Test func followUpAndTestChainsAreLeftAlone() {
        let alarm = spec()
        let now = date(2026, 11, 6, 7, 30)
        let cal = calendar()
        let planned = PlannedChain(
            alarmID: alarm.id, day: date(2026, 11, 6), start: date(2026, 11, 6, 7, 45), count: 4, interval: 180,
            timeZoneID: cal.timeZone.identifier, signature: "x"
        )
        let plan = SchedulePlanner.plan(
            specs: [alarm],
            existing: [chain(from: planned, kind: .followUp), chain(from: planned, kind: .test)],
            now: now, calendar: cal
        )
        #expect(plan.cancel.isEmpty)
    }

    @Test func oldChainsExpire() {
        let alarm = spec()
        let cal = calendar()
        let old = chain(from: PlannedChain(
            alarmID: alarm.id, day: date(2026, 11, 3), start: date(2026, 11, 3, 7), count: 3, interval: 180,
            timeZoneID: cal.timeZone.identifier, signature: "x"
        ))
        let plan = SchedulePlanner.plan(specs: [alarm], existing: [old], now: date(2026, 11, 5, 20), calendar: cal)
        #expect(plan.expire == [old])
    }

    @Test func slotBudgetKeepsTheNearestMornings() {
        let now = date(2026, 11, 5, 20, 0)
        let plan = SchedulePlanner.plan(specs: [spec(length: 10)], existing: [], now: now, slotBudget: 25, calendar: calendar())
        #expect(plan.create.count == 2)
        #expect(plan.create.first?.start == date(2026, 11, 6, 7))
    }

    @Test func twoAlarmsAreOrderedByTime() {
        let early = spec(hour: 6)
        let late = spec(hour: 9)
        let plan = SchedulePlanner.plan(
            specs: [late, early], existing: [], now: date(2026, 11, 5, 20),
            slotBudget: 6, windowDays: 2, calendar: calendar()
        )
        // Budget of 6 with 3 alarms per chain: tomorrow's 6:00 and 9:00.
        #expect(plan.create.map(\.alarmID) == [early.id, late.id])
    }

    // MARK: Skipping

    @Test func skipHasToBeDoneTheDayBefore() {
        let cal = calendar()
        let now = date(2026, 11, 5, 22, 0)
        #expect(SkipPolicy.check(day: date(2026, 11, 5), skipped: [], now: now, calendar: cal) == .tooSoon)
        #expect(SkipPolicy.check(day: date(2026, 11, 6), skipped: [], now: now, calendar: cal) == .allowed)
    }

    @Test func atMostTwoSkipsInAWeek() {
        let cal = calendar()
        let now = date(2026, 11, 5, 22, 0)
        let skipped = [date(2026, 11, 6), date(2026, 11, 8)]
        #expect(SkipPolicy.check(day: date(2026, 11, 7), skipped: skipped, now: now, calendar: cal) == .weekLimit)
        // A third skip a week later is fine.
        #expect(SkipPolicy.check(day: date(2026, 11, 14), skipped: skipped, now: now, calendar: cal) == .allowed)
        // But 6 days after the first still falls in a window with both.
        #expect(SkipPolicy.check(day: date(2026, 11, 12), skipped: skipped, now: now, calendar: cal) == .weekLimit)
    }

    @Test func skippingTheSameDayAgainDoesntDoubleCount() {
        let cal = calendar()
        let now = date(2026, 11, 5, 22, 0)
        let skipped = [date(2026, 11, 6), date(2026, 11, 7)]
        #expect(SkipPolicy.check(day: date(2026, 11, 7), skipped: skipped, now: now, calendar: cal) == .allowed)
    }

    @Test func skippableDayIsNeverToday() {
        let cal = calendar()
        let now = date(2026, 11, 5, 6, 0) // before today's 7:00
        let occurrence = SchedulePlanner.skippableOccurrence(of: spec(), after: now, calendar: cal)
        #expect(occurrence?.day == date(2026, 11, 6))
    }

    @Test func weekdayMaskRoundTrips() {
        let days: Set<Int> = [1, 3, 7]
        #expect(WakeAlarm.weekdays(from: WakeAlarm.mask(for: days)) == days)
        #expect(WakeAlarm.mask(for: .weekdays) == 0b0111110)
    }
}
