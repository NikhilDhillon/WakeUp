import Foundation

/// Which mission the morning alarm uses. Stored as the mission's UUID
/// string under `key` (read it with `@AppStorage(ActiveMission.key)`).
enum ActiveMission {
    static let key = "activeMissionID"

    /// The chosen mission, or the oldest one if the choice is missing.
    static func resolve(id: String, in missions: [Mission]) -> Mission? {
        missions.first { $0.id.uuidString == id } ?? missions.first
    }

    /// An alarm's own proof if it has one and it still exists; otherwise
    /// the default proof, otherwise the oldest one. A deleted proof can't
    /// leave an alarm with nothing to check against.
    static func resolve(preferred: String?, fallback: String, in missions: [Mission]) -> Mission? {
        if let preferred, let match = missions.first(where: { $0.id.uuidString == preferred }) {
            return match
        }
        return resolve(id: fallback, in: missions)
    }
}
