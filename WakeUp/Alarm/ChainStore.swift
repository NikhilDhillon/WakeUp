import Foundation

/// Remembers which alarms belong to the current wake chain, so the app can
/// cancel the rest of the chain once you've proven you're up.
struct ChainStore {
    private let defaults: UserDefaults
    private let idsKey = "wakeChain.alarmIDs"
    private let startKey = "wakeChain.start"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ids: [UUID] {
        (defaults.stringArray(forKey: idsKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    /// When the first alarm in the chain rings.
    var start: Date? {
        defaults.object(forKey: startKey) as? Date
    }

    func save(ids: [UUID], start: Date) {
        defaults.set(ids.map(\.uuidString), forKey: idsKey)
        defaults.set(start, forKey: startKey)
    }

    func clear() {
        defaults.removeObject(forKey: idsKey)
        defaults.removeObject(forKey: startKey)
    }
}
