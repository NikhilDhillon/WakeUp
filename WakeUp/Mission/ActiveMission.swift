import Foundation

/// Which mission the morning alarm uses. Stored as the mission's UUID
/// string under `key` (read it with `@AppStorage(ActiveMission.key)`).
enum ActiveMission {
    static let key = "activeMissionID"

    /// The chosen mission, or the oldest one if the choice is missing.
    static func resolve(id: String, in missions: [Mission]) -> Mission? {
        missions.first { $0.id.uuidString == id } ?? missions.first
    }
}
