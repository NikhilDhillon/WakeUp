import Foundation

/// The parts of an attempt the day summaries and the streak need.
struct AttemptInfo: Equatable, Sendable {
    var date: Date
    var kind: AttemptKind
    var passed: Bool
    /// When the alarm was set to ring; nil for older attempts.
    var alarmTime: Date? = nil
}

/// How one morning went.
struct MorningSummary: Equatable, Identifiable, Sendable {
    var day: Date
    /// When the alarm was set to ring, if that was saved.
    var alarmAt: Date? = nil
    /// When the first main check passed (when you were up).
    var upAt: Date?
    /// Main checks it took, including the one that passed.
    var tries: Int
    var followUpTries: Int
    var followUpPassed: Bool

    var id: Date { day }
}

/// How one of the last few days looks in the Mornings strip.
enum DayMark: Equatable, Sendable {
    /// A main check passed.
    case passed
    /// Today, with an alarm, still to come (or not yet proven).
    case upcoming
    /// An alarm rang that day and no photo passed.
    case missed
    /// No alarm rang (none set, skipped, or turned off), or nothing is known.
    case none
}

enum HistoryMath {
    /// The last `count` days ending today, oldest first, each with its mark.
    /// Past days go by what happened, not by today's alarms, so turning an
    /// alarm off (or on) never rewrites them: a pass is `.passed`, a morning
    /// whose alarm rang out without a pass (`missedDays`) is `.missed`, and
    /// anything else is `.none`. Today is `.upcoming` while an alarm is still
    /// due (`todayHasAlarm`).
    static func recentDays(
        passDays: Set<Date>,
        missedDays: Set<Date>,
        todayHasAlarm: Bool,
        now: Date,
        count: Int = 7,
        calendar: Calendar = .current
    ) -> [(day: Date, mark: DayMark)] {
        let passes = Set(passDays.map { calendar.startOfDay(for: $0) })
        let misses = Set(missedDays.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)

        return (0..<max(count, 0)).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            if passes.contains(day) { return (day, .passed) }
            if misses.contains(day) { return (day, .missed) }
            if day == today, todayHasAlarm { return (day, .upcoming) }
            return (day, .none)
        }
    }

    /// One summary per day that had attempts, newest first.
    static func summaries(of attempts: [AttemptInfo], calendar: Calendar = .current) -> [MorningSummary] {
        // Naps are mornings' opposite: a day with only a nap isn't a morning.
        Dictionary(grouping: attempts.filter { $0.kind != .nap }) { calendar.startOfDay(for: $0.date) }
            .map { day, items in
                let main = items.filter { $0.kind == .wake }.sorted { $0.date < $1.date }
                let followUps = items.filter { $0.kind == .followUp }
                let firstPass = main.firstIndex { $0.passed }
                return MorningSummary(
                    day: day,
                    // The alarm the morning's first photo answered.
                    alarmAt: main.lazy.compactMap(\.alarmTime).first,
                    upAt: firstPass.map { main[$0].date },
                    tries: firstPass.map { $0 + 1 } ?? main.count,
                    followUpTries: followUps.count,
                    followUpPassed: followUps.contains { $0.passed }
                )
            }
            .sorted { $0.day > $1.day }
    }

    /// One finished nap, as its History row.
    struct NapSummary: Equatable, Identifiable, Sendable {
        var id: UUID
        var startedAt: Date
        var minutes: Int
        var snoozes: Int
        /// When a proof passed; nil = the nap rang out unanswered.
        var upAt: Date?
        /// Photos it took, including the one that passed.
        var tries: Int
    }

    /// Finished naps, newest first. A nap's tries are the nap photos taken
    /// from its start until it ended (or until the next nap began).
    static func napSummaries(records: [NapRecord], attempts: [AttemptInfo]) -> [NapSummary] {
        let napAttempts = attempts.filter { $0.kind == .nap }
        let ordered = records.sorted { $0.startedAt < $1.startedAt }
        return ordered.enumerated().map { index, record in
            let nextStart = index + 1 < ordered.count ? ordered[index + 1].startedAt : .distantFuture
            let end = record.upAt ?? .distantFuture
            let tries = napAttempts.filter { $0.date >= record.startedAt && $0.date < nextStart && $0.date <= end }.count
            return NapSummary(
                id: record.id,
                startedAt: record.startedAt,
                minutes: max(Int((record.duration / 60).rounded()), 1),
                snoozes: record.snoozesUsed,
                upAt: record.upAt,
                tries: tries
            )
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    /// "Nap · 20 min · snoozed twice · up at 4:04 PM, 1 try".
    static func napLine(_ nap: NapSummary, locale: Locale = .current) -> String {
        var parts = ["Nap", "\(nap.minutes) min"]
        switch nap.snoozes {
        case 0: break
        case 1: parts.append("snoozed once")
        case 2: parts.append("snoozed twice")
        default: parts.append("snoozed \(nap.snoozes) times")
        }
        if let upAt = nap.upAt {
            parts.append("up at " + upAt.formatted(.dateTime.hour().minute().locale(locale)))
        } else {
            parts.append("not up")
        }
        let line = parts.joined(separator: " · ")
        guard nap.tries > 0 else { return line }
        return line + ", " + (nap.tries == 1 ? "1 try" : "\(nap.tries) tries")
    }

    /// An alarm's time of day and days, for guessing which one a photo answered.
    struct AlarmTimeOfDay: Equatable, Sendable {
        var hour: Int
        var minute: Int
        var weekdays: Set<Int>
    }

    /// The longest gap between an alarm and a photo that still counts as
    /// answering it, when guessing.
    static let likelyAlarmWindow: TimeInterval = 3 * 3600

    /// For attempts saved before the alarm time was kept: the latest alarm
    /// set for the photo's weekday that rang at or before the photo, up to
    /// three hours earlier. A guess from today's alarms, so it can be off if
    /// an alarm has moved since.
    static func likelyAlarm(
        before photo: Date, alarms: [AlarmTimeOfDay], calendar: Calendar = .current
    ) -> Date? {
        let weekday = calendar.component(.weekday, from: photo)
        return alarms
            .filter { $0.weekdays.contains(weekday) }
            .compactMap { calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: photo) }
            .filter { $0 <= photo && photo.timeIntervalSince($0) <= likelyAlarmWindow }
            .max()
    }

    /// How long after the alarm you were up: "On time", "5 min after the
    /// alarm", "1 h 20 min after the alarm". Under a minute counts as on time.
    static func upAfterAlarm(alarmAt: Date, upAt: Date) -> String {
        let minutes = max(Int(upAt.timeIntervalSince(alarmAt) / 60), 0)
        guard minutes > 0 else { return "On time" }
        let (h, m) = (minutes / 60, minutes % 60)
        let gap = switch (h, m) {
        case (0, _): "\(m) min"
        case (_, 0): "\(h) h"
        default: "\(h) h \(m) min"
        }
        return "\(gap) after the alarm"
    }

    /// Mornings in a row on which a main check passed, from what actually
    /// happened: only a morning whose alarm rang out with no pass
    /// (`missedDays`) breaks it. Days with no alarm, skips, and alarms you
    /// turned off neither count nor break it, so changing your alarms later
    /// never changes a streak you've already earned.
    static func streak(
        passDays: Set<Date>,
        missedDays: Set<Date>,
        now: Date,
        calendar: Calendar = .current
    ) -> Int {
        let passes = Set(passDays.map { calendar.startOfDay(for: $0) })
        let misses = Set(missedDays.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        guard let oldest = (passes.union(misses)).min() else { return 0 }

        var count = 0
        var day = today
        while day >= oldest {
            if passes.contains(day) {
                count += 1
            } else if misses.contains(day) {
                // An alarm rang out with no pass. (A pass that day wins, if a
                // second alarm went unanswered after you were already up.)
                break
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
