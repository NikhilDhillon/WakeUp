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

/// What the AI says about one proof photo: for each check, the probability
/// that its statement is true. Whether that's a pass is decided here, in
/// code, so the rules stay predictable.
struct Verdict: Equatable, Sendable {
    var probabilities: [ProofCheck: Double]
    /// A short note written by the AI. Only the Responses API gives one;
    /// the Decisions API only returns probabilities.
    var reason: String?

    /// How likely this check came out the way you want (0–1). A missing
    /// answer counts as 0, so it can never pass by accident.
    func confidence(_ check: ProofCheck) -> Double {
        guard let p = probabilities[check] else { return 0 }
        return check.wantsYes ? p : 1 - p
    }

    /// The weakest check's confidence.
    var overallConfidence: Double {
        ProofCheck.allCases.map(confidence).min() ?? 0
    }

    /// Every check that didn't reach `threshold`, in plain words.
    func problems(threshold: Double) -> [String] {
        ProofCheck.allCases
            .filter { confidence($0) < threshold }
            .map(\.problem)
    }

    func passes(threshold: Double) -> Bool {
        problems(threshold: threshold).isEmpty
    }
}
