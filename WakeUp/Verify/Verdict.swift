import Foundation

/// One thing the AI checks about a proof photo. The raw value is the name
/// sent to the API.
enum ProofCheck: String, CaseIterable, Codable, Sendable {
    case samePlace = "same_place"
    case personPresent = "person_present"
    case matchesDescription = "matches_description"
    case challengeCompleted = "challenge_completed"
    case appearsAwake = "appears_awake"
    case screenOrPrint = "looks_like_photo_of_screen_or_print"

    /// For every check except the screen one, "yes" is what you want.
    var wantsYes: Bool { self != .screenOrPrint }

    /// Short name for lists.
    var title: String {
        switch self {
        case .samePlace: "Right place"
        case .personPresent: "Person in photo"
        case .matchesDescription: "Matches description"
        case .challengeCompleted: "Challenge done"
        case .appearsAwake: "Looks awake"
        case .screenOrPrint: "Not a screen or print"
        }
    }

    /// Shown to you when this check fails.
    var problem: String {
        switch self {
        case .samePlace: "This doesn't look like the place in your reference photos."
        case .personPresent: "You need to be in the photo."
        case .matchesDescription: "The photo doesn't match your description."
        case .challengeCompleted: "Today's challenge isn't clearly visible."
        case .appearsAwake: "You don't look up yet."
        case .screenOrPrint: "This looks like a photo of a screen or a printout."
        }
    }
}

/// Who judged a photo.
enum CheckSource: String, Codable, Sendable {
    case decisions
    case responses
    /// The weaker check on the phone (Vision), used when OpenAI can't be reached.
    case offline

    var title: String {
        switch self {
        case .decisions: "Decisions API"
        case .responses: "Responses API"
        case .offline: "On this phone"
        }
    }
}

/// How sure the AI must be about each check. The strictness level sets the
/// base; a few checks get a small adjustment (the place check is the main
/// guard against cheating, so it's held to a higher bar, while a face in
/// dim morning light is judged more kindly). These offsets are starting
/// values: `eval/run_eval.py` shows whether they suit your photos.
struct ProofThresholds: Equatable, Sendable {
    var base: Double
    var offsets: [ProofCheck: Double] = ProofThresholds.defaultOffsets

    static let defaultOffsets: [ProofCheck: Double] = [
        .samePlace: 0.05,
        .appearsAwake: -0.10,
    ]

    /// The same bar for every check.
    static func uniform(_ value: Double) -> ProofThresholds {
        ProofThresholds(base: value, offsets: [:])
    }

    func threshold(for check: ProofCheck) -> Double {
        min(max(base + (offsets[check] ?? 0), 0), 1)
    }
}

/// What the AI says about one proof photo: for each check, the probability
/// that its statement is true. Whether that's a pass is decided here, in
/// code, so the rules stay predictable.
struct Verdict: Equatable, Sendable {
    var probabilities: [ProofCheck: Double]
    /// A short note written by the AI. Only the Responses API gives one;
    /// the Decisions API only returns probabilities.
    var reason: String?
    var method: CheckSource = .decisions
    /// The checks that were actually judged. The on-phone check can only
    /// judge two of the six; the others don't count for or against.
    var evaluated: Set<ProofCheck> = Set(ProofCheck.allCases)
    /// Input tokens OpenAI billed for this check, when it said.
    var inputTokens: Int?

    /// How likely this check came out the way you want (0–1). A missing
    /// answer counts as 0, so it can never pass by accident.
    func confidence(_ check: ProofCheck) -> Double {
        guard let p = probabilities[check] else { return 0 }
        return check.wantsYes ? p : 1 - p
    }

    /// The weakest judged check's confidence.
    var overallConfidence: Double {
        weakestCheck.map(confidence) ?? 0
    }

    var weakestCheck: ProofCheck? {
        ProofCheck.allCases.filter { evaluated.contains($0) }.min { confidence($0) < confidence($1) }
    }

    /// Every judged check that didn't reach its bar, in plain words.
    func problems(using thresholds: ProofThresholds) -> [String] {
        ProofCheck.allCases
            .filter { evaluated.contains($0) && confidence($0) < thresholds.threshold(for: $0) }
            .map(\.problem)
    }

    func passes(using thresholds: ProofThresholds) -> Bool {
        problems(using: thresholds).isEmpty
    }

    /// Every judged check that didn't reach `threshold` (the same bar for all).
    func problems(threshold: Double) -> [String] {
        problems(using: .uniform(threshold))
    }

    func passes(threshold: Double) -> Bool {
        passes(using: .uniform(threshold))
    }
}
