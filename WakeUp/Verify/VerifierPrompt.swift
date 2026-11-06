import Foundation

/// The instructions and answer format sent to the AI.
enum VerifierPrompt {
    // MARK: Decisions API

    /// Context sent once, before the photos.
    static let decisionsContext = """
    You check whether someone has really gotten out of bed in the morning. \
    You get reference photos of a place, the person's own description of what \
    their proof photo should show, a small challenge they must do in the photo, \
    and a new photo taken just now with the app's camera. Judge only the new \
    photo. Be strict but fair: an honest, slightly blurry or dim morning photo \
    should pass; a different room, nobody in the shot, or a missing challenge \
    should not.
    """

    /// The yes/no statement for one check. The API returns the probability
    /// that it's true.
    static func question(for check: ProofCheck, request: VerificationRequest) -> String {
        switch check {
        case .samePlace:
            "The new photo was taken in the same place as the reference photos. Angle, zoom and lighting may differ; look for the same fixtures, walls, tiles, furniture or layout."
        case .personPresent:
            "A real person is in the new photo (a face, or at least the body part doing the challenge)."
        case .matchesDescription:
            "The new photo shows what this description says: \(request.description)"
        case .challengeCompleted:
            "The person in the new photo is clearly doing this challenge: \(request.challenge)"
        case .appearsAwake:
            "The person in the new photo looks up and about: eyes open, upright, not lying in bed."
        case .screenOrPrint:
            "The new photo is a picture of a screen or of a printed photo (bezels, glare, moire, pixel grid, paper edges) rather than a live scene."
        }
    }

    // MARK: Responses API

    static let instructions = """
    You check whether someone has really gotten out of bed in the morning. \
    You get reference photos of a place, the person's own description of what \
    their proof photo should show, a small challenge they must do in the photo, \
    and a new photo taken just now with the app's camera.

    Judge only the new photo, and answer every field honestly:
    - same_place: the new photo was taken in the same place as the reference \
    photos. Angle, zoom and lighting may differ; look for the same fixtures, \
    walls, tiles, furniture or layout.
    - person_present: a real person is in the photo (a face, or at least the \
    body part doing the challenge).
    - matches_description: the photo shows what the description says.
    - challenge_completed: the person is clearly doing the challenge.
    - appears_awake: the person looks up and about (eyes open, upright, not \
    lying in bed).
    - looks_like_photo_of_screen_or_print: signs the new photo is a picture of \
    a screen or a printed photo (bezels, glare, moiré, pixel grid, paper edges).
    - confidence: from 0 to 1, how sure you are that this is a genuine, live \
    proof that matches everything above.
    - reason: one or two short, friendly sentences to the person saying what \
    you saw. If something is missing, say what to fix.

    Be strict but fair: an honest, slightly blurry or dim morning photo should \
    pass; a different room, nobody in the shot, or a missing challenge should not.
    """

    static func userText(for request: VerificationRequest) -> String {
        let time = request.capturedAt.formatted(date: .omitted, time: .shortened)
        return """
        Description of the proof photo: \(request.description)
        Today's challenge: \(request.challenge)
        Photo taken at: \(time)
        """
    }

    /// JSON schema for `Verdict`. Strict mode needs every field required and
    /// no extra fields.
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "same_place": ["type": "boolean"],
            "person_present": ["type": "boolean"],
            "matches_description": ["type": "boolean"],
            "challenge_completed": ["type": "boolean"],
            "appears_awake": ["type": "boolean"],
            "looks_like_photo_of_screen_or_print": ["type": "boolean"],
            "confidence": ["type": "number"],
            "reason": ["type": "string"],
        ],
        "required": [
            "same_place", "person_present", "matches_description", "challenge_completed",
            "appears_awake", "looks_like_photo_of_screen_or_print", "confidence", "reason",
        ],
        "additionalProperties": false,
    ]
}
