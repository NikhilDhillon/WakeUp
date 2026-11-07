import Foundation
import Testing
@testable import WakeUp

private func calendar(_ zone: String = "America/Vancouver") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.locale = Locale(identifier: "en_US")
    calendar.firstWeekday = 1
    return calendar
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, calendar cal: Calendar = calendar()) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// MARK: Status pill

struct HomeStatusTests {
    private func make(
        _ warnings: [HealthWarning] = [],
        lastError: String? = nil,
        notDetermined: Bool = false,
        hasAlarms: Bool = true,
        hasEnabled: Bool = true,
        nextRing: Date? = nil,
        now: Date = date(2026, 11, 6, 20)
    ) -> HomeStatus? {
        HomeStatus.make(
            warnings: warnings, lastError: lastError, authorizationNotDetermined: notDetermined,
            hasAlarms: hasAlarms, hasEnabledAlarm: hasEnabled, nextRing: nextRing, now: now, calendar: calendar()
        )
    }

    @Test func hiddenWithNoAlarms() {
        #expect(make(hasAlarms: false) == nil)
    }

    @Test func readyForTomorrow() {
        let status = make(nextRing: date(2026, 11, 7, 6, 45))
        #expect(status?.isReady == true)
        #expect(status?.readyText == "Ready for tomorrow")
    }

    @Test func readyForALaterDayNamesIt() {
        // Friday evening; the next ring is Monday.
        let status = make(nextRing: date(2026, 11, 9, 6, 45))
        #expect(status?.readyText == "Ready for Monday")
    }

    @Test func readyForTodayWhenItRingsLaterToday() {
        let status = make(nextRing: date(2026, 11, 6, 23), now: date(2026, 11, 6, 5))
        #expect(status?.readyText == "Ready for today")
    }

    @Test func tomorrowAcrossDaylightSavingEnd() {
        // Clocks go back on Nov 1, 2026; the day gap must still be 1.
        let now = date(2026, 10, 31, 22)
        let status = make(nextRing: date(2026, 11, 1, 6, 45), now: now)
        #expect(status?.readyText == "Ready for tomorrow")
    }

    @Test func severityOrderFollowsThePlan() {
        let all: [HealthWarning] = [
            .lowPowerMode, .buildExpiring(daysLeft: 2), .lowBattery, .cannotCheckPhoto,
            .noProof, .cameraDenied, .alarmsBlocked,
        ]
        let status = make(all, lastError: "boom", notDetermined: true)!
        #expect(status.problems.map(\.id) == [
            "lastError", "alarmsBlocked", "cameraDenied", "noProof", "cannotCheckPhoto",
            "lowBattery", "buildExpiring", "lowPowerMode", "authorization",
        ])
        #expect(status.worst?.action == .retry)
        #expect(status.extraCount == 8)
    }

    @Test func eachWarningHasItsShortTitleAndAction() {
        let cases: [(HealthWarning, String, StatusAction?)] = [
            (.alarmsBlocked, "Alarms are off for WakeUp", .openSystemSettings),
            (.cameraDenied, "Camera is blocked", .openSystemSettings),
            (.noProof, "Choose a place", .chooseProof),
            (.cannotCheckPhoto, "Photo check isn't set up", .setUpPhotoCheck),
            (.lowBattery, "Battery low, plug in tonight", nil),
            (.buildExpiring(daysLeft: 2), "Build expires in 2 days", nil),
            (.buildExpiring(daysLeft: 1), "Build expires in 1 day", nil),
            (.lowPowerMode, "Low Power Mode is on", .showDetails),
        ]
        for (warning, title, action) in cases {
            let problem = HomeStatus.problem(for: warning)
            #expect(problem.title == title)
            #expect(problem.action == action)
            #expect(problem.detail == warning.message)
        }
    }

    @Test func allAlarmsOffSaysSo() {
        let status = make(hasEnabled: false)!
        #expect(status.worst?.title == "No alarm is on")
        #expect(status.worst?.action == nil)
    }

    @Test func blockedAlarmsOutrankNoAlarmOn() {
        let status = make([.alarmsBlocked], hasEnabled: false)!
        #expect(status.problems.map(\.id) == ["alarmsBlocked", "noAlarmOn"])
        #expect(status.extraCount == 1)
    }

    @Test func notDeterminedAsksForPermission() {
        let status = make(notDetermined: true)!
        #expect(status.worst?.title == "Allow alarms")
        #expect(status.worst?.action == .requestAuthorization)
    }
}

// MARK: Difficulty presets

struct AlarmDifficultyTests {
    @Test func presetsMatchTheirOwnValues() {
        for level in AlarmDifficulty.presets {
            let v = level.values!
            #expect(AlarmDifficulty.matching(
                chainLength: v.chainLength, intervalMinutes: v.intervalMinutes, followUpMinutes: v.followUpMinutes
            ) == level)
        }
    }

    @Test func presetValuesAreTheDocumentedOnes() {
        #expect(AlarmDifficulty.gentle.values == .init(chainLength: 5, intervalMinutes: 5, followUpMinutes: 0))
        #expect(AlarmDifficulty.firm.values == .init(chainLength: 10, intervalMinutes: 3, followUpMinutes: 0))
        #expect(AlarmDifficulty.relentless.values == .init(chainLength: 10, intervalMinutes: 2, followUpMinutes: 0))
    }

    @Test func noPresetHasAFollowUp() {
        for level in AlarmDifficulty.presets {
            #expect(level.values?.followUpMinutes == 0)
        }
    }

    @Test func alarmsOnTheOldPresetsLoseTheirFollowUp() {
        // Old Firm and old Relentless: follow-up off, so they match again.
        #expect(AlarmDifficulty.followUpAfterPresetChange(chainLength: 10, intervalMinutes: 3, followUpMinutes: 12) == 0)
        #expect(AlarmDifficulty.followUpAfterPresetChange(chainLength: 10, intervalMinutes: 2, followUpMinutes: 10) == 0)
        // Anything you set yourself stays as it is.
        #expect(AlarmDifficulty.followUpAfterPresetChange(chainLength: 7, intervalMinutes: 4, followUpMinutes: 12) == 12)
        #expect(AlarmDifficulty.followUpAfterPresetChange(chainLength: 10, intervalMinutes: 3, followUpMinutes: 15) == 15)
    }

    @Test func presetsStayInsideTheModelsLimits() {
        for level in AlarmDifficulty.presets {
            let v = level.values!
            #expect(WakeAlarm.chainLengthRange.contains(v.chainLength))
            #expect(WakeAlarm.chainIntervalRange.contains(v.intervalMinutes))
            #expect(v.followUpMinutes == 0 || WakeAlarm.followUpChoices.contains(v.followUpMinutes))
        }
    }

    @Test func oddValuesAreCustom() {
        #expect(AlarmDifficulty.matching(chainLength: 7, intervalMinutes: 3, followUpMinutes: 12) == .custom)
        #expect(AlarmDifficulty.matching(chainLength: 10, intervalMinutes: 3, followUpMinutes: 15) == .custom)
        #expect(AlarmDifficulty.custom.values == nil)
    }

    @Test func aNewAlarmsDefaultsAreFirm() {
        let alarm = WakeAlarm()
        #expect(AlarmDifficulty.matching(
            chainLength: alarm.chainLength, intervalMinutes: alarm.chainIntervalMinutes, followUpMinutes: alarm.followUpMinutes
        ) == .firm)
    }

    @Test func chipText() {
        #expect(AlarmDifficulty.chipText(chainLength: 10, intervalMinutes: 3, followUpMinutes: 0) == "Firm · 10 rings")
        // A follow-up added by hand makes it Custom.
        #expect(AlarmDifficulty.chipText(chainLength: 10, intervalMinutes: 3, followUpMinutes: 12) == "Custom · 10 rings")
        #expect(AlarmDifficulty.chipText(chainLength: 1, intervalMinutes: 3, followUpMinutes: 12) == "Custom · 1 ring")
    }

    @Test func summaryIsTwoShortLines() {
        #expect(AlarmDifficulty.summary(chainLength: 10, intervalMinutes: 3, followUpMinutes: 12)
            == "Rings 10 times, 3 min apart, until a photo passes.\nChecks again 12 min after you pass.")
        #expect(AlarmDifficulty.summary(chainLength: 5, intervalMinutes: 5, followUpMinutes: 0)
            == "Rings 5 times, 5 min apart, until a photo passes.\nNo check after you pass.")
        #expect(AlarmDifficulty.summary(chainLength: 1, intervalMinutes: 3, followUpMinutes: 0)
            == "Rings once, until a photo passes.\nNo check after you pass.")
    }
}

// MARK: Week strip

struct RecentDaysTests {
    // Friday Nov 6, 2026.
    private let now = date(2026, 11, 6, 7)

    private func marks(
        passes: [Date] = [], missed: [Date] = [], todayHasAlarm: Bool = true, now: Date? = nil, count: Int = 7
    ) -> [DayMark] {
        HistoryMath.recentDays(
            passDays: Set(passes), missedDays: Set(missed), todayHasAlarm: todayHasAlarm,
            now: now ?? self.now, count: count, calendar: calendar()
        ).map(\.mark)
    }

    @Test func sevenDaysOldestFirstEndingToday() {
        let days = HistoryMath.recentDays(
            passDays: [], missedDays: [], todayHasAlarm: true, now: now, calendar: calendar()
        ).map(\.day)
        #expect(days.count == 7)
        #expect(days.first == date(2026, 10, 31))
        #expect(days.last == date(2026, 11, 6))
    }

    @Test func passedMissedUpcomingAndNone() {
        // Sat 31, Sun 1, Mon 2, Tue 3, Wed 4, Thu 5, Fri 6.
        let result = marks(
            passes: [date(2026, 11, 2, 6, 50), date(2026, 11, 3, 6, 50), date(2026, 11, 5, 6, 50)],
            missed: [date(2026, 11, 4)]
        )
        #expect(result == [.none, .none, .passed, .passed, .missed, .passed, .upcoming])
    }

    @Test func todayCountsOnceProven() {
        #expect(marks(passes: [date(2026, 11, 6, 6, 50)]).last == .passed)
    }

    @Test func pastDaysWithNothingRecordedAreGrey() {
        // No pass and nothing rang out: no alarm, a skip, or one turned off.
        #expect(marks()[0..<6].allSatisfy { $0 == .none })
    }

    @Test func todayWithNoAlarmDueIsGrey() {
        #expect(marks(todayHasAlarm: false).last == DayMark.none)
    }

    @Test func pastDaysDontDependOnTodaysAlarms() {
        let passes = [date(2026, 11, 3, 6, 50)]
        let missed = [date(2026, 11, 4)]
        let withAlarm = marks(passes: passes, missed: missed, todayHasAlarm: true)
        let without = marks(passes: passes, missed: missed, todayHasAlarm: false)
        #expect(Array(withAlarm.dropLast()) == Array(without.dropLast()))
    }

    @Test func daylightSavingDayIsOneDay() {
        // Seven days ending Mon Nov 2 span the Nov 1 clock change.
        let result = marks(passes: [date(2026, 11, 1, 6, 50)], now: date(2026, 11, 2, 7))
        #expect(result.count == 7)
        #expect(result[result.count - 2] == .passed)
        #expect(result.last == .upcoming)
    }
}

// MARK: Ring position

struct RingPositionTests {
    private func chain(start: Date, interval: TimeInterval = 180, count: Int = 10) -> ScheduledChain {
        ScheduledChain(
            id: UUID(), alarmID: UUID(), kind: .main, day: start, start: start, interval: interval,
            slotIDs: (0..<count).map { _ in UUID() }, timeZoneID: "America/Vancouver", signature: ""
        )
    }

    private let start = date(2026, 11, 6, 6, 45)

    @Test func firstRing() {
        let position = chain(start: start).ringPosition(at: start.addingTimeInterval(20))
        #expect(position.current == 1)
        #expect(position.total == 10)
        #expect(position.next == start.addingTimeInterval(180))
    }

    @Test func secondRing() {
        let position = chain(start: start).ringPosition(at: start.addingTimeInterval(190))
        #expect(position.current == 2)
        #expect(position.next == start.addingTimeInterval(360))
    }

    @Test func exactlyOnARing() {
        let position = chain(start: start).ringPosition(at: start.addingTimeInterval(180))
        #expect(position.current == 2)
    }

    @Test func lastRingHasNoNext() {
        let position = chain(start: start).ringPosition(at: start.addingTimeInterval(180 * 9 + 5))
        #expect(position.current == 10)
        #expect(position.next == nil)
    }

    @Test func afterTheChainStaysOnTheLastRing() {
        let position = chain(start: start).ringPosition(at: start.addingTimeInterval(3 * 3600))
        #expect(position.current == 10)
        #expect(position.next == nil)
    }

    @Test func beforeTheStartIsRingOne() {
        let position = chain(start: start).ringPosition(at: start.addingTimeInterval(-60))
        #expect(position.current == 1)
    }

    @Test func singleAlarmChain() {
        let position = chain(start: start, count: 1).ringPosition(at: start.addingTimeInterval(10))
        #expect(position.current == 1)
        #expect(position.total == 1)
        #expect(position.next == nil)
    }

    @Test func noSlotsDoesNotCrash() {
        let position = chain(start: start, count: 0).ringPosition(at: start.addingTimeInterval(10))
        #expect(position.current == 1)
        #expect(position.total == 1)
    }

    @Test func ringNumberUsesElapsedTimeAcrossDaylightSaving() {
        // 1:50 am Nov 1, 2026 in Vancouver happens twice; elapsed seconds, not
        // wall-clock minutes, decide the ring.
        let cal = calendar()
        let dstStart = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 50))!
        let position = chain(start: dstStart, interval: 300).ringPosition(at: dstStart.addingTimeInterval(3600 + 100))
        #expect(position.current == 10)
    }
}

// MARK: Skip captions

struct SkipCaptionTests {
    private let now = date(2026, 11, 6, 12)   // Friday

    @Test func allowedHasNoReason() {
        #expect(SkipPolicy.unavailableReason(day: date(2026, 11, 7), skipped: [], now: now, calendar: calendar()) == nil)
    }

    @Test func todayIsTooSoon() {
        #expect(
            SkipPolicy.unavailableReason(day: date(2026, 11, 6), skipped: [], now: now, calendar: calendar())
                == "Skip by the night before"
        )
    }

    @Test func weekLimitSaysHowManyAreUsed() {
        let skipped = [date(2026, 11, 8), date(2026, 11, 9)]
        #expect(
            SkipPolicy.unavailableReason(day: date(2026, 11, 10), skipped: skipped, now: now, calendar: calendar())
                == "2 skips used this week"
        )
    }

    @Test func skipsUsedIgnoresTheTargetItself() {
        let skipped = [date(2026, 11, 8), date(2026, 11, 9)]
        #expect(SkipPolicy.skipsUsed(near: date(2026, 11, 9), skipped: skipped, calendar: calendar()) == 1)
    }

    @Test func skipsUsedIgnoresFarAwayDays() {
        let skipped = [date(2026, 11, 1), date(2026, 11, 20)]
        #expect(SkipPolicy.skipsUsed(near: date(2026, 11, 10), skipped: skipped, calendar: calendar()) == 0)
    }

    @Test func weekBoundaryWindowsStillCount() {
        // Sat Nov 7 and Fri Nov 13 are 6 days apart, so they share a window with Wed Nov 11... not Nov 14+.
        let skipped = [date(2026, 11, 7), date(2026, 11, 8)]
        #expect(SkipPolicy.skipsUsed(near: date(2026, 11, 13), skipped: skipped, calendar: calendar()) == 2)
        #expect(SkipPolicy.skipsUsed(near: date(2026, 11, 14), skipped: skipped, calendar: calendar()) == 1)
        #expect(SkipPolicy.skipsUsed(near: date(2026, 11, 15), skipped: skipped, calendar: calendar()) == 0)
    }

    @Test func undoingAnExistingSkipIsNotBlocked() {
        // The target day is excluded, so a skipped day can always be un-skipped.
        let skipped = [date(2026, 11, 8), date(2026, 11, 9)]
        #expect(SkipPolicy.unavailableReason(day: date(2026, 11, 9), skipped: skipped, now: now, calendar: calendar()) == nil)
    }
}

// MARK: Next Up card

struct NextUpTests {
    private func spec(
        hour: Int = 6, minute: Int = 45, weekdays: Set<Int> = .weekdays, enabled: Bool = true, skipped: [Date] = []
    ) -> AlarmSpec {
        AlarmSpec(
            id: UUID(), hour: hour, minute: minute, weekdays: weekdays, missionID: nil, chainLength: 10,
            chainInterval: 180, followUpDelay: 720, isEnabled: enabled, skippedDays: skipped
        )
    }

    private let now = date(2026, 11, 6, 23)   // Friday night

    @Test func earliestEnabledAlarmWins() {
        let early = spec(hour: 6, minute: 30, weekdays: .everyDay)
        let late = spec(hour: 6, minute: 45, weekdays: .everyDay)
        let pick = NextUp.pick(specs: [late, early], now: now, calendar: calendar())
        #expect(pick?.alarmID == early.id)
        #expect(pick?.ring == date(2026, 11, 7, 6, 30))
    }

    @Test func offAlarmsAreIgnoredWhenAnotherIsOn() {
        let off = spec(hour: 5, enabled: false)
        let on = spec(hour: 8, weekdays: .everyDay)
        #expect(NextUp.pick(specs: [off, on], now: now, calendar: calendar())?.alarmID == on.id)
    }

    @Test func everyAlarmOffShowsTheFirstGreyed() {
        let a = spec(hour: 8, enabled: false)
        let b = spec(hour: 6, enabled: false)
        let pick = NextUp.pick(specs: [a, b], now: now, calendar: calendar())
        #expect(pick?.alarmID == b.id)
        #expect(pick?.isOff == true)
    }

    @Test func heldAlarmStaysOnTheCardWhenTurnedOff() {
        // The card's alarm is switched off: the card keeps it, greyed, instead
        // of swapping in the next alarm (whose switch is still on).
        let turnedOff = spec(hour: 5, weekdays: .everyDay, enabled: false)
        let other = spec(hour: 8, weekdays: .everyDay)
        let pick = NextUp.pick(specs: [turnedOff, other], now: now, holding: turnedOff.id, calendar: calendar())
        #expect(pick?.alarmID == turnedOff.id)
        #expect(pick?.isOff == true)
    }

    @Test func heldAlarmStaysWhenAnEarlierOneIsTurnedOn() {
        let shown = spec(hour: 8, weekdays: .everyDay)
        let turnedOn = spec(hour: 5, weekdays: .everyDay)
        let pick = NextUp.pick(specs: [shown, turnedOn], now: now, holding: shown.id, calendar: calendar())
        #expect(pick?.alarmID == shown.id)
        #expect(pick?.ring == date(2026, 11, 7, 8, 45))
    }

    @Test func heldAlarmThatWasDeletedFallsBackToTheNextRing() {
        let on = spec(hour: 8, weekdays: .everyDay)
        #expect(NextUp.pick(specs: [on], now: now, holding: UUID(), calendar: calendar())?.alarmID == on.id)
    }

    @Test func noAlarmsNoPick() {
        #expect(NextUp.pick(specs: [], now: now, calendar: calendar()) == nil)
    }

    @Test func skippedMorningMovesTheCardToTheNextRealRing() {
        // Weekdays only: Friday night, Monday is next. Skip Monday and it's Tuesday.
        let skipping = spec(skipped: [date(2026, 11, 9)])
        let pick = NextUp.pick(specs: [skipping], now: now, calendar: calendar())
        #expect(pick?.ring == date(2026, 11, 10, 6, 45))
    }

    @Test func countdownInHoursAndMinutes() {
        let ring = date(2026, 11, 7, 6, 45)
        #expect(NextUp.countdownLabel(to: ring, now: date(2026, 11, 6, 23, 8), calendar: calendar()) == "NEXT · IN 7 H 37 M")
        #expect(NextUp.spokenCountdown(to: ring, now: date(2026, 11, 6, 23, 8), calendar: calendar()) == "in 7 hours 37 minutes")
    }

    @Test func countdownWholeHoursAndSingleUnits() {
        let ring = date(2026, 11, 7, 6, 0)
        #expect(NextUp.countdownLabel(to: ring, now: date(2026, 11, 7, 5, 0), calendar: calendar()) == "NEXT · IN 1 H")
        #expect(NextUp.spokenCountdown(to: ring, now: date(2026, 11, 7, 5, 0), calendar: calendar()) == "in 1 hour")
        #expect(NextUp.countdownLabel(to: ring, now: date(2026, 11, 7, 5, 59), calendar: calendar()) == "NEXT · IN 1 M")
        #expect(NextUp.spokenCountdown(to: ring, now: date(2026, 11, 7, 5, 59), calendar: calendar()) == "in 1 minute")
    }

    @Test func overADayAwayNamesTheWeekday() {
        let ring = date(2026, 11, 9, 6, 45)   // Monday
        #expect(NextUp.countdownLabel(to: ring, now: date(2026, 11, 7, 6, 0), calendar: calendar()) == "NEXT · MON")
        #expect(NextUp.spokenCountdown(to: ring, now: date(2026, 11, 7, 6, 0), calendar: calendar()) == "on Monday")
    }

    @Test func skipChipNamesTheDay() {
        // Friday 11pm; weekdays; the first morning after today is Monday.
        let chip = NextUp.skipChip(for: spec(), now: now, calendar: calendar())
        #expect(chip?.title == "Skip Monday")
        #expect(chip?.disabledReason == nil)
        #expect(chip?.isUndo == false)
    }

    @Test func skipChipBecomesUndoForASkippedDay() {
        let chip = NextUp.skipChip(for: spec(skipped: [date(2026, 11, 9)]), now: now, calendar: calendar())
        #expect(chip?.title == "Undo skip")
        #expect(chip?.isUndo == true)
        #expect(chip?.disabledReason == nil)
    }

    @Test func skipChipIsGreyedWhenTheWeekIsFull() {
        let chip = NextUp.skipChip(
            for: spec(weekdays: .everyDay, skipped: [date(2026, 11, 8), date(2026, 11, 9)]),
            now: now, calendar: calendar()
        )
        // The first skippable day (Sat Nov 7) shares a window with both skips.
        #expect(chip?.title == "Skip Saturday")
        #expect(chip?.disabledReason == "2 skips used this week")
    }

    @Test func noSkipChipForAnAlarmThatIsOff() {
        #expect(NextUp.skipChip(for: spec(enabled: false), now: now, calendar: calendar()) == nil)
    }
}
