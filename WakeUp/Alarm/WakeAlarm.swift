import Foundation
import SwiftData

/// A saved wake-up alarm: a time, the days it repeats, which proof it asks
/// for and how it rings. `spec` is the copy the scheduler works from.
@Model
final class WakeAlarm {
    var id: UUID = UUID()
    var label: String = ""
    var hour: Int = 7
    var minute: Int = 0
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday) as a bit mask,
    /// bit 0 = Sunday. Stored as a number so it survives migrations.
    var weekdaysMask: Int = 0b0111110
    /// The proof's UUID string. Empty = whatever proof is the default.
    var missionID: String = ""
    var isEnabled: Bool = true
    var chainLength: Int = 10
    var chainIntervalMinutes: Int = 3
    var followUpMinutes: Int = 0
    var skippedDays: [Date] = []
    var soundRaw: String = AlarmSound.standard.rawValue
    var createdAt: Date = Date()

    static let chainLengthRange = 1...10
    static let chainIntervalRange = 1...10
    static let followUpChoices = [0, 5, 10, 12, 15, 20, 30]

    init(hour: Int = 7, minute: Int = 0, weekdays: Set<Int> = .weekdays) {
        self.hour = hour
        self.minute = minute
        self.weekdaysMask = Self.mask(for: weekdays)
    }

    var weekdays: Set<Int> {
        get { Self.weekdays(from: weekdaysMask) }
        set { weekdaysMask = Self.mask(for: newValue) }
    }

    var spec: AlarmSpec {
        AlarmSpec(
            id: id,
            hour: hour,
            minute: minute,
            weekdays: weekdays,
            missionID: missionID.isEmpty ? nil : missionID,
            chainLength: min(max(chainLength, Self.chainLengthRange.lowerBound), Self.chainLengthRange.upperBound),
            chainInterval: Double(min(max(chainIntervalMinutes, Self.chainIntervalRange.lowerBound), Self.chainIntervalRange.upperBound)) * 60,
            followUpDelay: Double(max(followUpMinutes, 0)) * 60,
            isEnabled: isEnabled,
            skippedDays: skippedDays,
            sound: soundRaw
        )
    }

    /// The time as a `Date` today, for pickers.
    var timeOfDay: Date {
        get { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = parts.hour ?? hour
            minute = parts.minute ?? minute
        }
    }

    // MARK: Weekday helpers

    static func mask(for weekdays: Set<Int>) -> Int {
        weekdays.filter { (1...7).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    static func weekdays(from mask: Int) -> Set<Int> {
        Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
    }

    /// "Every day", "Weekdays", "Weekends" or "Mon, Wed, Fri".
    static func summary(of weekdays: Set<Int>, calendar: Calendar = .current) -> String {
        switch weekdays {
        case .everyDay: return "Every day"
        case .weekdays: return "Weekdays"
        case [1, 7]: return "Weekends"
        case []: return "Never"
        default:
            let names = calendar.shortWeekdaySymbols
            // Start the week on the user's first weekday.
            let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
            return ordered.filter(weekdays.contains).map { names[$0 - 1] }.joined(separator: ", ")
        }
    }
}
