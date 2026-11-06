import Foundation

/// Checks a proof photo with OpenAI's Responses API. Slower and pricier
/// than the Decisions API, but the AI also writes a short reason. The
/// model answers yes/no per check plus one overall confidence, which is
/// turned into a probability per check.
struct ResponsesVerifier: WakeVerifier {
    var apiKey: String?
    var model: String
    var endpoint = URL(string: "https://api.openai.com/v1/responses")!
    var session: URLSession = .shared

    func verify(_ request: VerificationRequest) async throws -> Verdict {
        guard let apiKey, !apiKey.isEmpty else { throw VerifierError.missingAPIKey }
        let (data, status) = try await OpenAIHTTP.post(
            Self.body(for: request, model: model), to: endpoint, apiKey: apiKey, session: session
        )
        return try Self.parse(data: data, status: status)
    }

    // MARK: Request

    static func body(for request: VerificationRequest, model: String) -> [String: Any] {
        var content: [[String: Any]] = [
            ["type": "input_text", "text": VerifierPrompt.userText(for: request)],
        ]
        for (index, photo) in request.referencePhotos.enumerated() {
            content.append(["type": "input_text", "text": "Reference photo \(index + 1) of \(request.referencePhotos.count):"])
            content.append(OpenAIHTTP.imagePart(photo))
        }
        content.append(["type": "input_text", "text": "New photo, taken just now with the in-app camera:"])
        content.append(OpenAIHTTP.imagePart(request.photo))

        var body: [String: Any] = [
            "model": model,
            "instructions": VerifierPrompt.instructions,
            "input": [["role": "user", "content": content]],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "wake_verdict",
                    "strict": true,
                    "schema": VerifierPrompt.schema,
                ],
            ],
            "store": false,
        ]
        // Reasoning models think less at "low" effort, which keeps a 6am
        // check fast. Older non-reasoning models reject the field, so only
        // send it to model families known to take it.
        if usesReasoning(model) {
            body["reasoning"] = ["effort": "low"]
        }
        return body
    }

    static func usesReasoning(_ model: String) -> Bool {
        ["gpt-5", "gpt-6", "o1", "o3", "o4"].contains { model.hasPrefix($0) }
    }

    // MARK: Response

    /// The JSON the model is told to write.
    struct Answer: Decodable {
        var samePlace: Bool
        var personPresent: Bool
        var matchesDescription: Bool
        var challengeCompleted: Bool
        var appearsAwake: Bool
        var looksLikePhotoOfScreenOrPrint: Bool
        var confidence: Double
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

        /// A "yes" becomes `confidence`, a "no" becomes `1 - confidence`.
        var verdict: Verdict {
            let c = min(max(confidence, 0), 1)
            func p(_ yes: Bool) -> Double { yes ? c : 1 - c }
            return Verdict(
                probabilities: [
                    .samePlace: p(samePlace),
                    .personPresent: p(personPresent),
                    .matchesDescription: p(matchesDescription),
                    .challengeCompleted: p(challengeCompleted),
                    .appearsAwake: p(appearsAwake),
                    .screenOrPrint: p(looksLikePhotoOfScreenOrPrint),
                ],
                reason: reason
            )
        }
    }

    static func parse(data: Data, status: Int) throws -> Verdict {
        let json = try OpenAIHTTP.json(from: data, status: status)

        if json["status"] as? String == "incomplete" {
            let details = json["incomplete_details"] as? [String: Any]
            throw VerifierError.incomplete(details?["reason"] as? String ?? "unknown")
        }

        // `output` can hold reasoning items before the message; find the
        // message's text (or a refusal).
        let output = json["output"] as? [[String: Any]] ?? []
        for item in output where item["type"] as? String == "message" {
            for part in item["content"] as? [[String: Any]] ?? [] {
                switch part["type"] as? String {
                case "output_text":
                    guard let text = part["text"] as? String,
                          let answer = try? JSONDecoder().decode(Answer.self, from: Data(text.utf8))
                    else { throw VerifierError.unreadableResponse }
                    return answer.verdict
                case "refusal":
                    throw VerifierError.refused(part["refusal"] as? String ?? "No reason given.")
                default:
                    continue
                }
            }
        }
        throw VerifierError.unreadableResponse
    }
}
