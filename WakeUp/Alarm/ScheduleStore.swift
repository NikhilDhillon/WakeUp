import Foundation

/// Remembers, on this phone, the alarms the user set (`specs`) and the
/// AlarmKit chains scheduled from them (`chains`). It replaces the old
/// one-chain `ChainStore`. The specs are a mirror of the SwiftData alarms so
/// the scheduler, the alarm button and the background refresh can work
/// without opening the database.
struct ScheduleStore {
    private let defaults: UserDefaults
    private let chainsKey = "schedule.chains"
    private let specsKey = "schedule.specs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var chains: [ScheduledChain] {
        get { read([ScheduledChain].self, key: chainsKey) ?? [] }
        nonmutating set { write(newValue, key: chainsKey) }
    }

    var specs: [AlarmSpec] {
        get { read([AlarmSpec].self, key: specsKey) ?? [] }
        nonmutating set { write(newValue, key: specsKey) }
    }

    func spec(for id: UUID) -> AlarmSpec? {
        specs.first { $0.id == id }
    }

    func add(_ chain: ScheduledChain) {
        chains = chains.filter { $0.id != chain.id } + [chain]
    }

    func remove(chainID: UUID) {
        chains = chains.filter { $0.id != chainID }
    }

    func chain(containing slotID: UUID) -> ScheduledChain? {
        chains.first { $0.allSlotIDs.contains(slotID) }
    }

    func clear() {
        defaults.removeObject(forKey: chainsKey)
        defaults.removeObject(forKey: napKey)
    }

    // MARK: Nap

    private let napKey = "schedule.nap"
    private let napRecordsKey = "history.naps"
    /// How many finished naps are remembered.
    static let napRecordsKept = 100

    /// The nap that's set, ringing or waiting for its follow-up. nil when none.
    var nap: NapSession? {
        get { read(NapSession.self, key: napKey) }
        nonmutating set {
            if let newValue {
                write(newValue, key: napKey)
            } else {
                defaults.removeObject(forKey: napKey)
            }
        }
    }

    /// Finished naps, oldest first, for History.
    var napRecords: [NapRecord] {
        read([NapRecord].self, key: napRecordsKey) ?? []
    }

    func addNapRecord(_ record: NapRecord) {
        let kept = napRecords.filter { $0.id != record.id } + [record]
        write(Array(kept.suffix(Self.napRecordsKept)), key: napRecordsKey)
    }

    /// "Clear history" forgets these along with the photo attempts.
    func clearNapRecords() {
        defaults.removeObject(forKey: napRecordsKey)
    }

    /// Marks the nap as rung once its chain has started, which locks
    /// "Cancel nap". Returns the nap as saved.
    @discardableResult
    func markNapRungIfStarted(now: Date) -> NapSession? {
        guard var nap, !nap.hasRung,
              chains.contains(where: { $0.kind == .nap && $0.alarmID == nap.id && $0.hasStarted(at: now) })
        else { return self.nap }
        nap.hasRung = true
        self.nap = nap
        return nap
    }

    // MARK: Missed mornings

    private let missedDaysKey = "history.missedDays"
    /// How long missed mornings are remembered.
    static let missedDaysKept = 400

    /// Mornings (start of day) whose alarm rang out without a pass. With the
    /// passes in History, this is what the streak and week strip go by, so
    /// later changes to your alarms don't rewrite past days.
    var missedDays: Set<Date> {
        Set(read([Date].self, key: missedDaysKey) ?? [])
    }

    func recordMissed(day: Date, now: Date = .now, calendar: Calendar = .current) {
        let cutoff = calendar.date(byAdding: .day, value: -Self.missedDaysKept, to: now) ?? .distantPast
        var days = missedDays.filter { $0 >= cutoff }
        days.insert(calendar.startOfDay(for: day))
        write(days.sorted(), key: missedDaysKey)
    }

    /// "Clear history" forgets these along with the photo attempts.
    func clearMissedDays() {
        defaults.removeObject(forKey: missedDaysKey)
    }

    private func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
