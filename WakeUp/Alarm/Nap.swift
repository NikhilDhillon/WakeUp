import Foundation

/// A one-off nap timer: sleep for a while, then ring like a morning alarm.
/// It is saved in `ScheduleStore` (UserDefaults), so the alarm buttons, the
/// Stop intent and a restart can all find it without opening the database.
/// Only one nap exists at a time.
struct NapSession: Codable, Equatable, Identifiable, Sendable {
    /// Also the chain's `alarmID`.
    var id: UUID
    var startedAt: Date
    /// When the first ring goes off. Moves later with each snooze.
    var ringsAt: Date
    var duration: TimeInterval
    /// The proof's UUID string. nil = the default proof.
    var missionID: String?
    /// The proof's name when the nap started, for the alarm's title and the card.
    var proofName: String
    var chainLength: Int
    var chainInterval: TimeInterval
    /// Seconds after a pass before the "Still at your desk?" check. 0 = off.
    var followUpDelay: TimeInterval
    /// `AlarmSound` raw value.
    var sound: String = AlarmSound.standard.rawValue
    /// 0 to 3. 0 = no snooze.
    var snoozesAllowed: Int
    /// 5, 10 or 15 minutes.
    var snoozeLength: TimeInterval
    var snoozesUsed: Int = 0
    /// The first ring has gone off. Locks "Cancel nap".
    var hasRung = false
    /// A proof passed. The nap is over; only its follow-up check may be left.
    var passedAt: Date?

    /// A nap is 5 minutes to 3 hours: shorter isn't a nap, longer is a mistake.
    static let durationRange: ClosedRange<Int> = 5...180
    static let snoozeCountRange = 0...3
    static let snoozeLengthChoices = [5, 10, 15]
    static let quickDurations = [10, 20, 30, 45, 60, 90]
    /// The chain's name in `ScheduledChain.signature`.
    static let signature = "nap"

    var snoozesLeft: Int { max(snoozesAllowed - snoozesUsed, 0) }

    /// True once the snoozes are all used. A nap with none to begin with
    /// isn't told "No snoozes left".
    var usedAllSnoozes: Bool { snoozesAllowed > 0 && snoozesLeft == 0 }

    /// "Cancel nap" is allowed only before the first ring.
    func canCancel(at now: Date) -> Bool {
        !hasRung && passedAt == nil && ringsAt > now
    }

    enum Stage: Equatable, Sendable {
        /// Counting down to the first ring.
        case waiting
        /// Snoozed: counting down to the next chain.
        case snoozed
        /// The chain has started and no proof has passed.
        case ringing
        /// A proof passed. Only the follow-up check is left.
        case done
    }

    func stage(at now: Date) -> Stage {
        if passedAt != nil { return .done }
        if ringsAt > now { return snoozesUsed > 0 ? .snoozed : .waiting }
        return .ringing
    }

    /// "Napping until 3:42 PM", "Snoozed until 3:52 PM" or "Nap's over".
    func statusText(at now: Date) -> String {
        let time = ringsAt.formatted(date: .omitted, time: .shortened)
        switch stage(at: now) {
        case .waiting: return "Napping until \(time)"
        case .snoozed: return "Snoozed until \(time)"
        case .ringing: return "Nap's over"
        case .done: return "Still at your desk?"
        }
    }

    /// "1 snooze left", "2 snoozes left" or "No snoozes left".
    var snoozesLeftText: String {
        switch snoozesLeft {
        case 0: "No snoozes left"
        case 1: "1 snooze left"
        default: "\(snoozesLeft) snoozes left"
        }
    }

    /// Builds a nap that starts at `now`. The duration is held to the limits (5 min to 3 h).
    static func make(
        now: Date,
        minutes: Int,
        missionID: String?,
        proofName: String,
        chainLength: Int,
        chainIntervalMinutes: Int,
        followUpMinutes: Int,
        sound: String = AlarmSound.standard.rawValue,
        snoozes: Int,
        snoozeMinutes: Int,
        allowShort: Bool = false,
        id: UUID = UUID()
    ) -> NapSession {
        // `allowShort` is for the developer's quick nap, which rings in a minute.
        let shortest = allowShort ? 1 : durationRange.lowerBound
        let clamped = min(max(minutes, shortest), durationRange.upperBound)
        let seconds = Double(clamped) * 60
        return NapSession(
            id: id,
            startedAt: now,
            ringsAt: now.addingTimeInterval(seconds),
            duration: seconds,
            missionID: missionID,
            proofName: proofName,
            chainLength: min(max(chainLength, WakeAlarm.chainLengthRange.lowerBound), WakeAlarm.chainLengthRange.upperBound),
            chainInterval: Double(min(max(chainIntervalMinutes, WakeAlarm.chainIntervalRange.lowerBound), WakeAlarm.chainIntervalRange.upperBound)) * 60,
            followUpDelay: Double(max(followUpMinutes, 0)) * 60,
            sound: sound,
            snoozesAllowed: min(max(snoozes, snoozeCountRange.lowerBound), snoozeCountRange.upperBound),
            snoozeLength: Double(max(snoozeMinutes, 1)) * 60
        )
    }

    /// The nap after a snooze at `now`: one more used, ringing again in
    /// `snoozeLength`. nil when none are left, so a snooze can't go past the limit.
    func snoozed(at now: Date) -> NapSession? {
        guard snoozesLeft > 0, passedAt == nil else { return nil }
        var copy = self
        copy.snoozesUsed += 1
        copy.ringsAt = now.addingTimeInterval(snoozeLength)
        copy.hasRung = true
        return copy
    }
}

extension NapSession {
    // Naps saved by an older build may lack newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        ringsAt = try c.decode(Date.self, forKey: .ringsAt)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        missionID = try c.decodeIfPresent(String.self, forKey: .missionID)
        proofName = try c.decodeIfPresent(String.self, forKey: .proofName) ?? ""
        chainLength = try c.decode(Int.self, forKey: .chainLength)
        chainInterval = try c.decode(TimeInterval.self, forKey: .chainInterval)
        followUpDelay = try c.decode(TimeInterval.self, forKey: .followUpDelay)
        sound = try c.decodeIfPresent(String.self, forKey: .sound) ?? AlarmSound.standard.rawValue
        snoozesAllowed = try c.decode(Int.self, forKey: .snoozesAllowed)
        snoozeLength = try c.decode(TimeInterval.self, forKey: .snoozeLength)
        snoozesUsed = try c.decodeIfPresent(Int.self, forKey: .snoozesUsed) ?? 0
        hasRung = try c.decodeIfPresent(Bool.self, forKey: .hasRung) ?? false
        passedAt = try c.decodeIfPresent(Date.self, forKey: .passedAt)
    }
}

/// How a finished nap shows in History. Snoozes aren't photo attempts, so
/// the count is kept here when the nap ends.
struct NapRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var startedAt: Date
    var duration: TimeInterval
    var snoozesUsed: Int
    /// When a proof passed. nil = the nap rang out and was never answered.
    var upAt: Date?
}

/// What the Nap sheet opens on: the last choices for a nap.
struct NapDefaults: Codable, Equatable, Sendable {
    var minutes = 20
    var missionID: String?
    var chainLength = 10
    var intervalMinutes = 3
    var followUpMinutes = 0
    var snoozes = 2
    var snoozeMinutes = 10

    /// How long after a pass the "Still at your desk?" check comes, when on.
    static let followUpChoices = [5, 10, 15]
    static let relentlessFollowUpMinutes = 10

    private static let key = "nap.defaults"

    static func load(from defaults: UserDefaults = .standard) -> NapDefaults {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(NapDefaults.self, from: data)
        else { return NapDefaults() }
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// What a ring's sound and gap are, looked up for a chain's alarm.
struct RingSettings: Equatable, Sendable {
    var sound: String
    var interval: TimeInterval

    /// A nap has no `AlarmSpec`, so the saved nap is checked first.
    static func resolve(alarmID: UUID, nap: NapSession?, spec: AlarmSpec?) -> RingSettings? {
        if let nap, nap.id == alarmID {
            return RingSettings(sound: nap.sound, interval: nap.chainInterval)
        }
        return spec.map { RingSettings(sound: $0.sound, interval: $0.chainInterval) }
    }
}

extension NapSession {
    /// "19:42", or "1:05:09" over an hour. Never below 0:00.
    static func countdownText(from now: Date, to ringsAt: Date) -> String {
        let total = max(Int(ringsAt.timeIntervalSince(now).rounded(.up)), 0)
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// "19 minutes 42 seconds", for VoiceOver.
    static func spokenCountdown(from now: Date, to ringsAt: Date) -> String {
        let total = max(Int(ringsAt.timeIntervalSince(now).rounded(.up)), 0)
        let (h, m) = (total / 3600, total % 3600 / 60)
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if parts.isEmpty { parts.append("less than a minute") }
        return parts.joined(separator: " ")
    }
}
