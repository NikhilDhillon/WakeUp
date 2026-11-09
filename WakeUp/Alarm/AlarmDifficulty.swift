import Foundation

/// How hard the alarm is to ignore. A label worked out from the alarm's
/// three ringing fields, so it needs no stored value.
enum AlarmDifficulty: String, CaseIterable, Identifiable, Sendable {
    case gentle
    case firm
    case relentless
    /// The values match none of the presets.
    case custom

    var id: String { rawValue }

    /// The presets a person can pick (Custom appears only when it applies).
    static let presets: [AlarmDifficulty] = [.gentle, .firm, .relentless]

    struct Values: Equatable, Sendable {
        var chainLength: Int
        var intervalMinutes: Int
        /// 0 = no follow-up.
        var followUpMinutes: Int
    }

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .firm: "Firm"
        case .relentless: "Relentless"
        case .custom: "Custom"
        }
    }

    /// The values a preset sets. nil for Custom.
    var values: Values? {
        switch self {
        case .gentle: Values(chainLength: 5, intervalMinutes: 5, followUpMinutes: 0)
        case .firm: Values(chainLength: 10, intervalMinutes: 3, followUpMinutes: 0)
        case .relentless: Values(chainLength: 10, intervalMinutes: 2, followUpMinutes: 0)
        case .custom: nil
        }
    }

    var summary: String {
        switch self {
        case .gentle: "5 rings, 5 minutes apart"
        case .firm: "10 rings, 3 minutes apart"
        case .relentless: "10 rings, 2 minutes apart"
        case .custom: "Your own settings"
        }
    }

    /// What Firm and Relentless used to be, when they included a follow-up.
    /// Alarms still set exactly like this get the follow-up turned off.
    static let oldPresetsWithFollowUp: [Values] = [
        Values(chainLength: 10, intervalMinutes: 3, followUpMinutes: 12),
        Values(chainLength: 10, intervalMinutes: 2, followUpMinutes: 10),
    ]

    /// The follow-up an alarm should have now: 0 if it was on an old preset
    /// that included one, otherwise unchanged.
    static func followUpAfterPresetChange(chainLength: Int, intervalMinutes: Int, followUpMinutes: Int) -> Int {
        let current = Values(chainLength: chainLength, intervalMinutes: intervalMinutes, followUpMinutes: followUpMinutes)
        return oldPresetsWithFollowUp.contains(current) ? 0 : followUpMinutes
    }

    /// The preset these values match, or `.custom`.
    static func matching(chainLength: Int, intervalMinutes: Int, followUpMinutes: Int) -> AlarmDifficulty {
        let current = Values(chainLength: chainLength, intervalMinutes: intervalMinutes, followUpMinutes: followUpMinutes)
        return presets.first { $0.values == current } ?? .custom
    }

    /// "Firm · 10 rings".
    static func chipText(chainLength: Int, intervalMinutes: Int, followUpMinutes: Int) -> String {
        let level = matching(chainLength: chainLength, intervalMinutes: intervalMinutes, followUpMinutes: followUpMinutes)
        return "\(level.title) · \(chainLength) ring\(chainLength == 1 ? "" : "s")"
    }

    /// "Rings 10 times, 3 min apart, until a photo passes."
    static func ringsSummary(chainLength: Int, intervalMinutes: Int) -> String {
        chainLength == 1
            ? "Rings once, until a photo passes."
            : "Rings \(chainLength) times, \(intervalMinutes) min apart, until a photo passes."
    }

    /// Two short lines under the difficulty controls:
    /// "Rings 10 times, 3 min apart, until a photo passes."
    /// "Checks again 12 min after you pass."
    static func summary(chainLength: Int, intervalMinutes: Int, followUpMinutes: Int) -> String {
        let rings = ringsSummary(chainLength: chainLength, intervalMinutes: intervalMinutes)
        let followUp = followUpMinutes > 0
            ? "Checks again \(followUpMinutes) min after you pass."
            : "No check after you pass."
        return rings + "\n" + followUp
    }
}
