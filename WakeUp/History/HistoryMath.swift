import Foundation

/// The parts of an attempt the day summaries and the streak need.
struct AttemptInfo: Equatable, Sendable {
    var date: Date
    var kind: AttemptKind
    var passed: Bool
}

/// How one morning went.
struct MorningSummary: Equatable, Identifiable, Sendable {
    var day: Date
    /// When the first main check passed (when you were up).
    var upAt: Date?
    /// Main checks it took, including the one that passed.
    var tries: Int
    var followUpTries: Int
    var followUpPassed: Bool

    var id: Date { day }
}

enum HistoryMath {
    /// One summary per day that had attempts, newest first.
    static func summaries(of attempts: [AttemptInfo], calendar: Calendar = .current) -> [MorningSummary] {
        Dictionary(grouping: attempts) { calendar.startOfDay(for: $0.date) }
            .map { day, items in
                let main = items.filter { $0.kind == .wake }.sorted { $0.date < $1.date }
                let followUps = items.filter { $0.kind == .followUp }
                let firstPass = main.firstIndex { $0.passed }
                return MorningSummary(
                    day: day,
                    upAt: firstPass.map { main[$0].date },
                    tries: firstPass.map { $0 + 1 } ?? main.count,
                    followUpTries: followUps.count,
                    followUpPassed: followUps.contains { $0.passed }
                )
            }
            .sorted { $0.day > $1.day }
    }

    /// Mornings in a row, ending today or yesterday, on which a main check
    /// passed. Days without an alarm, and days you skipped, neither count
    /// nor break the streak. Today doesn't break it while it's still open.
    static func streak(
        passDays: Set<Date>,
        alarmWeekdays: Set<Int>,
        skippedDays: Set<Date>,
        now: Date,
        calendar: Calendar = .current
    ) -> Int {
        let required = alarmWeekdays.isEmpty ? Set<Int>.everyDay : alarmWeekdays
        let passes = Set(passDays.map { calendar.startOfDay(for: $0) })
        let skips = Set(skippedDays.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)

        var count = 0
        var day = today
        for _ in 0..<3650 {
            let isToday = day == today
            let counts = required.contains(calendar.component(.weekday, from: day)) && !skips.contains(day)
            if counts {
                if passes.contains(day) {
                    count += 1
                } else if !isToday {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
