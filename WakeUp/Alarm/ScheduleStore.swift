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
