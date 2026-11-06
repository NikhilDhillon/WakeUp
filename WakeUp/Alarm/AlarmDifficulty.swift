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
        case .firm: Values(chainLength: 10, intervalMinutes: 3, followUpMinutes: 12)
        case .relentless: Values(chainLength: 10, intervalMinutes: 2, followUpMinutes: 10)
        case .custom: nil
        }
    }

    var summary: String {
        switch self {
        case .gentle: "5 rings, 5 minutes apart, no follow-up"
        case .firm: "10 rings, 3 minutes apart, checks again after 12 minutes"
        case .relentless: "10 rings, 2 minutes apart, checks again after 10 minutes"
        case .custom: "Your own settings"
        }
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
}
