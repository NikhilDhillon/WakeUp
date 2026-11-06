import Foundation

/// Everything the scheduler needs to know about one wake-up alarm. It is a
/// plain value copy of the SwiftData `WakeAlarm`, so it can be saved to
/// UserDefaults and read when the app wakes up without opening the database
/// (for example from the alarm's "Prove I'm up" button).
struct AlarmSpec: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var hour: Int
    var minute: Int
    /// `Calendar` weekday numbers: 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int>
    var missionID: String?
    var chainLength: Int
    /// Seconds between the alarms of one chain.
    var chainInterval: TimeInterval
    /// Seconds after a pass before the "Still up?" check. 0 = off.
    var followUpDelay: TimeInterval
    var isEnabled: Bool
    /// Start-of-day dates the user chose to skip.
    var skippedDays: [Date]
    /// `AlarmSound` raw value.
    var sound: String = AlarmSound.standard.rawValue

    /// Alarms in the follow-up chain that rings after a pass.
    static let followUpChainLength = 4
    /// Follow-up delay used after an offline pass, even if the alarm has none.
    static let offlineFollowUpDelay: TimeInterval = 10 * 60
}

/// One chain of fixed-date alarms that AlarmKit knows about.
struct ScheduledChain: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A morning's main wake-up chain.
        case main
        /// The "Still up?" chain after a pass.
        case followUp
        /// A developer test chain. The planner never touches these.
        case test
    }

    var id: UUID
    var alarmID: UUID
    var kind: Kind
    /// Start of the day this chain belongs to.
    var day: Date
    /// When the first alarm rings.
    var start: Date
    var interval: TimeInterval
    /// The AlarmKit IDs that were actually scheduled.
    var slotIDs: [UUID]
    var timeZoneID: String
    /// Changes when the alarm's time, length, interval or time zone changes.
    var signature: String

    /// When the last alarm in the chain rings.
    var lastRing: Date {
        start.addingTimeInterval(interval * Double(max(slotIDs.count - 1, 0)))
    }

    /// How long after the last ring you can still open the app and be sent
    /// to the proof screen.
    static let owedGrace: TimeInterval = 2 * 3600

    func hasStarted(at now: Date) -> Bool { start <= now }

    func isExpired(at now: Date) -> Bool {
        lastRing.addingTimeInterval(Self.owedGrace) < now
    }
}

/// A chain the planner wants created.
struct PlannedChain: Equatable, Sendable {
    var alarmID: UUID
    var day: Date
    var start: Date
    var count: Int
    var interval: TimeInterval
    var timeZoneID: String
    var signature: String
    var sound: String = AlarmSound.standard.rawValue
}

struct SchedulePlan: Equatable, Sendable {
    /// Future chains that no longer match any alarm (edited, disabled,
    /// deleted, skipped, time zone changed). Cancel their alarms.
    var cancel: [ScheduledChain] = []
    /// Chains whose time is long gone. Forget them.
    var expire: [ScheduledChain] = []
    var create: [PlannedChain] = []
}

/// The date math. Everything is a pure function of its inputs, so it can be
/// tested with fixed dates, time zones and daylight-saving changes.
enum SchedulePlanner {
    /// How many calendar days ahead to keep mornings scheduled, today included.
    static let windowDays = 4

    struct Occurrence: Equatable, Sendable {
        var day: Date
        var start: Date
        var isSkipped: Bool
    }

    /// The alarm's rings in the next `days` calendar days that are still in
    /// the future. A time that doesn't exist (daylight saving jumps) moves
    /// to the next valid time; a time that happens twice uses the first.
    static func occurrences(
        of spec: AlarmSpec,
        after now: Date,
        days: Int = windowDays,
        calendar: Calendar = .current
    ) -> [Occurrence] {
        let today = calendar.startOfDay(for: now)
        var result: [Occurrence] = []
        for offset in 0..<max(days, 0) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  spec.weekdays.contains(calendar.component(.weekday, from: day)),
                  let start = calendar.date(
                      bySettingHour: spec.hour, minute: spec.minute, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward
                  ),
                  start > now
            else { continue }
            let skipped = spec.skippedDays.contains { calendar.isDate($0, inSameDayAs: day) }
            result.append(Occurrence(day: day, start: start, isSkipped: skipped))
        }
        return result
    }

    /// The next time this alarm will actually ring, skipped days left out.
    static func nextRing(of spec: AlarmSpec, after now: Date, calendar: Calendar = .current) -> Date? {
        guard spec.isEnabled else { return nil }
        // A week plus a day always contains every chosen weekday.
        return occurrences(of: spec, after: now, days: 8, calendar: calendar)
            .first { !$0.isSkipped }?.start
    }

    /// The first morning after today, which is the earliest day you may skip.
    static func skippableOccurrence(of spec: AlarmSpec, after now: Date, calendar: Calendar = .current) -> Occurrence? {
        let today = calendar.startOfDay(for: now)
        return occurrences(of: spec, after: now, days: 8, calendar: calendar)
            .first { $0.day > today }
    }

    static func signature(of spec: AlarmSpec, calendar: Calendar = .current) -> String {
        "\(spec.hour):\(spec.minute)|\(spec.chainLength)|\(Int(spec.chainInterval))|\(calendar.timeZone.identifier)|\(spec.sound)"
    }

    /// Compares what should be scheduled with what is, and says what to
    /// change. `slotBudget` caps how many AlarmKit alarms the app uses in
    /// total (nearest mornings first), for when iOS has a limit.
    static func plan(
        specs: [AlarmSpec],
        existing: [ScheduledChain],
        now: Date,
        slotBudget: Int? = nil,
        windowDays: Int = windowDays,
        calendar: Calendar = .current
    ) -> SchedulePlan {
        var plan = SchedulePlan()

        var desired: [PlannedChain] = []
        for spec in specs where spec.isEnabled {
            let signature = signature(of: spec, calendar: calendar)
            for occurrence in occurrences(of: spec, after: now, days: windowDays, calendar: calendar)
            where !occurrence.isSkipped {
                desired.append(PlannedChain(
                    alarmID: spec.id,
                    day: occurrence.day,
                    start: occurrence.start,
                    count: spec.chainLength,
                    interval: spec.chainInterval,
                    timeZoneID: calendar.timeZone.identifier,
                    signature: signature,
                    sound: spec.sound
                ))
            }
        }
        desired.sort { $0.start < $1.start }

        var kept: [ScheduledChain] = []
        var matched = Set<Int>()
        for chain in existing {
            if chain.isExpired(at: now) {
                plan.expire.append(chain)
            } else if chain.kind != .main || chain.hasStarted(at: now) {
                // Follow-ups, test chains and any chain already ringing or
                // still owed are left alone.
                kept.append(chain)
            } else if let index = desired.indices.first(where: { i in
                !matched.contains(i)
                    && desired[i].alarmID == chain.alarmID
                    && calendar.isDate(desired[i].day, inSameDayAs: chain.day)
                    && desired[i].start == chain.start
                    && desired[i].signature == chain.signature
            }) {
                matched.insert(index)
                kept.append(chain)
            } else {
                plan.cancel.append(chain)
            }
        }

        var used = kept.reduce(0) { $0 + $1.slotIDs.count }
        for (index, planned) in desired.enumerated() where !matched.contains(index) {
            if let slotBudget, used + planned.count > slotBudget { break }
            used += planned.count
            plan.create.append(planned)
        }
        return plan
    }
}

/// The rules for "Skip tomorrow".
enum SkipPolicy {
    /// At most this many skipped days in any 7 days in a row.
    static let maxPerWeek = 2

    enum Result: Equatable {
        case allowed
        /// Skipping has to happen the day before at the latest.
        case tooSoon
        case weekLimit
    }

    static func check(day: Date, skipped: [Date], now: Date, calendar: Calendar = .current) -> Result {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: day)
        guard target > today else { return .tooSoon }
        let others = skipped.map { calendar.startOfDay(for: $0) }.filter { $0 != target }
        // Look at every 7-day window that contains the target day.
        for back in 0..<7 {
            guard let windowStart = calendar.date(byAdding: .day, value: -back, to: target),
                  let windowEnd = calendar.date(byAdding: .day, value: 7, to: windowStart)
            else { continue }
            let inWindow = others.filter { $0 >= windowStart && $0 < windowEnd }.count
            if inWindow + 1 > maxPerWeek { return .weekLimit }
        }
        return .allowed
    }
}

extension Set where Element == Int {
    static let everyDay: Set<Int> = Set(1...7)
    static let weekdays: Set<Int> = [2, 3, 4, 5, 6]
}

/// What an alarm sounds like.
enum AlarmSound: String, CaseIterable, Identifiable, Sendable {
    case standard
    /// A louder, harsher beeping tone bundled with the app (`WakeAlarm.wav`).
    case loud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .loud: "Loud beeps"
        }
    }

    /// The file in the app bundle, or nil for the system alarm sound.
    var fileName: String? {
        switch self {
        case .standard: nil
        case .loud: "WakeAlarm.wav"
        }
    }
}

extension AlarmSpec {
    // Alarms saved by an older build have no `sound`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        hour = try c.decode(Int.self, forKey: .hour)
        minute = try c.decode(Int.self, forKey: .minute)
        weekdays = try c.decode(Set<Int>.self, forKey: .weekdays)
        missionID = try c.decodeIfPresent(String.self, forKey: .missionID)
        chainLength = try c.decode(Int.self, forKey: .chainLength)
        chainInterval = try c.decode(TimeInterval.self, forKey: .chainInterval)
        followUpDelay = try c.decode(TimeInterval.self, forKey: .followUpDelay)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        skippedDays = try c.decode([Date].self, forKey: .skippedDays)
        sound = try c.decodeIfPresent(String.self, forKey: .sound) ?? AlarmSound.standard.rawValue
    }
}
