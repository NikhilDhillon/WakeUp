import Foundation

/// What the AI says about one proof photo. The AI only answers the
/// questions; whether that counts as a pass is decided here, in code, so
/// the rules stay predictable.
struct Verdict: Codable, Equatable, Sendable {
    var samePlace: Bool
    var personPresent: Bool
    var matchesDescription: Bool
    var challengeCompleted: Bool
    var appearsAwake: Bool
    var looksLikePhotoOfScreenOrPrint: Bool
    /// 0–1, how sure the AI is that this is a genuine proof.
    var confidence: Double
    /// Short explanation written to you.
    var reason: String

    enum CodingKeys: String, CodingKey {
        case samePlace = "same_place"
        case personPresent = "person_present"
        case matchesDescription = "matches_description"
        case challengeCompleted = "challenge_completed"
        case appearsAwake = "appears_awake"
        case looksLikePhotoOfScreenOrPrint = "looks_like_photo_of_screen_or_print"
        case confidence
        case reason
    }

    /// Everything that stopped the photo from passing, in plain words.
    func problems(threshold: Double) -> [String] {
        var problems: [String] = []
        if !samePlace { problems.append("This doesn't look like the place in your reference photos.") }
        if !personPresent { problems.append("You need to be in the photo.") }
        if !matchesDescription { problems.append("The photo doesn't match your description.") }
        if !challengeCompleted { problems.append("Today's challenge isn't clearly visible.") }
        if !appearsAwake { problems.append("You don't look up yet.") }
        if looksLikePhotoOfScreenOrPrint { problems.append("This looks like a photo of a screen or a printout.") }
        if problems.isEmpty, confidence < threshold {
            problems.append("The AI wasn't sure enough (\(Int((confidence * 100).rounded()))%, needs \(Int((threshold * 100).rounded()))%).")
        }
        return problems
    }

    func passes(threshold: Double) -> Bool {
        problems(threshold: threshold).isEmpty
    }
}
