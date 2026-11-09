import Foundation

/// Where this morning is. It is saved, so a crash or a restart in the
/// middle of the morning picks up in the right place.
///
/// ```
/// idle → ringing → passed → followUpRinging → done
///           ↑________|_________|   (a follow-up that rings again is just
///                                   another ring of the same morning)
/// ```
///
/// A nap uses the same phases, plus `.snoozed`: Stop (or the wake screen's
/// Snooze button) swaps the nap's chain for a new one that hasn't started,
/// and `sync` must not read that gap as a nap nobody answered.
struct WakeState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        /// Nothing is going on.
        case idle
        /// The main chain has started and no proof has passed yet.
        case ringing
        /// A proof passed; the follow-up check is waiting.
        case passed
        /// The follow-up chain has started.
        case followUpRinging
        /// The morning is finished.
        case done
        /// A nap was snoozed: its next chain is waiting to start.
        case snoozed
    }

    enum Outcome: String, Codable, Sendable {
        case stayedUp
        /// The follow-up chain rang out with no pass.
        case wentBackToBed
        case stoppedWithoutProof
        /// The main chain rang out and was never answered.
        case missed
    }

    var phase: Phase = .idle
    var alarmID: UUID?
    var morning: Date?
    /// What this ring asks for. Stays the same across retries and restarts.
    var challenge: Challenge?
    /// Failed or retaken checks in the current ring.
    var attempts = 0
    var passedAt: Date?
    var followUpAt: Date?
    var checkedOffline = false
    var lastOutcome: Outcome?
    /// This is a nap, not a morning: it isn't a missed morning when it
    /// rings out, and it has its own wording.
    var isNap = false

    /// The proof screen should be showing.
    var isAwaitingProof: Bool {
        phase == .ringing || phase == .followUpRinging
    }

    // MARK: Moving between phases

    /// Look at the scheduled chains and move to match them. Call it when the
    /// app opens, when an alarm button is tapped and when alarms change.
    mutating func sync(chains: [ScheduledChain], now: Date, calendar: Calendar = .current) {
        let live = chains.filter { !$0.isExpired(at: now) && $0.hasStarted(at: now) }

        if let followUp = live.filter({ $0.kind == .followUp }).min(by: { $0.start < $1.start }) {
            if phase != .followUpRinging {
                begin(
                    .followUpRinging, alarmID: followUp.alarmID, morning: followUp.day,
                    avoiding: challenge, isNap: followUp.belongsToNap
                )
            }
            return
        }

        if let main = live.filter({ $0.kind != .followUp }).min(by: { $0.start < $1.start }) {
            switch phase {
            case .idle, .done:
                begin(.ringing, alarmID: main.alarmID, morning: main.day, avoiding: nil, isNap: main.kind == .nap)
            case .passed:
                // Another alarm's chain began before the follow-up did.
                if main.alarmID != alarmID {
                    begin(.ringing, alarmID: main.alarmID, morning: main.day, avoiding: challenge, isNap: main.kind == .nap)
                }
            case .snoozed:
                if main.alarmID == alarmID {
                    // The snoozed nap rings again: same challenge, fresh tries.
                    phase = .ringing
                    attempts = 0
                } else {
                    begin(.ringing, alarmID: main.alarmID, morning: main.day, avoiding: challenge, isNap: main.kind == .nap)
                }
            case .ringing, .followUpRinging:
                break
            }
            return
        }

        // Nothing is ringing any more.
        switch phase {
        case .ringing, .snoozed:
            // A snoozed nap has a new chain waiting to start. That's not a
            // nap nobody answered.
            if isNap, chains.contains(where: {
                $0.kind == .nap && $0.alarmID == alarmID && !$0.isExpired(at: now) && !$0.hasStarted(at: now)
            }) {
                phase = .snoozed
                return
            }
            // The whole chain rang out with no proof.
            lastOutcome = .missed
            phase = .idle
        case .followUpRinging:
            lastOutcome = .wentBackToBed
            phase = .idle
        case .passed:
            // The follow-up chain is gone without ever ringing (cancelled
            // or the phone was off). Treat the morning as finished.
            if !chains.contains(where: { $0.kind == .followUp }) {
                lastOutcome = .stayedUp
                phase = .done
            }
        case .idle, .done:
            break
        }
    }

    /// A proof photo passed. `followUpDelay` is how long until the
    /// "Still up?" check; 0 ends the morning now. Returns the delay that
    /// was actually used.
    @discardableResult
    mutating func proofPassed(at now: Date, followUpDelay: TimeInterval, offline: Bool) -> TimeInterval {
        switch phase {
        case .followUpRinging:
            phase = .done
            lastOutcome = .stayedUp
            followUpAt = nil
            return 0
        default:
            // An offline check is weaker, so it always gets a follow-up.
            let delay = offline ? max(followUpDelay, AlarmSpec.offlineFollowUpDelay) : followUpDelay
            passedAt = now
            checkedOffline = offline
            attempts = 0
            if delay > 0 {
                phase = .passed
                followUpAt = now.addingTimeInterval(delay)
            } else {
                phase = .done
                lastOutcome = .stayedUp
                followUpAt = nil
            }
            return delay
        }
    }

    mutating func proofFailed() {
        attempts += 1
    }

    /// "Stop alarms without proof" (nothing to check against).
    mutating func stoppedWithoutProof() {
        phase = .done
        lastOutcome = .stoppedWithoutProof
        followUpAt = nil
    }

    mutating func reset() {
        self = WakeState()
    }

    /// "I'm up early" on a nap that hasn't rung (or is snoozed): the proof
    /// screen opens now. A snoozed nap keeps its challenge.
    mutating func beginNapEarly(alarmID: UUID, day: Date) {
        if isNap, self.alarmID == alarmID, phase == .ringing || phase == .snoozed {
            phase = .ringing
            return
        }
        begin(.ringing, alarmID: alarmID, morning: day, avoiding: nil, isNap: true)
    }

    private mutating func begin(
        _ phase: Phase, alarmID: UUID, morning: Date, avoiding previous: Challenge?, isNap: Bool = false
    ) {
        self.phase = phase
        self.alarmID = alarmID
        self.isNap = isNap
        self.morning = morning
        self.challenge = Challenge.random(excluding: previous)
        self.attempts = 0
        if phase == .ringing {
            passedAt = nil
            followUpAt = nil
            checkedOffline = false
            lastOutcome = nil
        }
    }
}

extension WakeState {
    // A state saved by an older build has no `isNap`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decodeIfPresent(Phase.self, forKey: .phase) ?? .idle
        alarmID = try c.decodeIfPresent(UUID.self, forKey: .alarmID)
        morning = try c.decodeIfPresent(Date.self, forKey: .morning)
        challenge = try c.decodeIfPresent(Challenge.self, forKey: .challenge)
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        passedAt = try c.decodeIfPresent(Date.self, forKey: .passedAt)
        followUpAt = try c.decodeIfPresent(Date.self, forKey: .followUpAt)
        checkedOffline = try c.decodeIfPresent(Bool.self, forKey: .checkedOffline) ?? false
        lastOutcome = try c.decodeIfPresent(Outcome.self, forKey: .lastOutcome)
        isNap = try c.decodeIfPresent(Bool.self, forKey: .isNap) ?? false
    }
}

/// Saves the `WakeState` on this phone.
struct WakeStateStore {
    private let defaults: UserDefaults
    private let key = "wake.state"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WakeState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(WakeState.self, from: data)
        else { return WakeState() }
        return state
    }

    func save(_ state: WakeState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
}
