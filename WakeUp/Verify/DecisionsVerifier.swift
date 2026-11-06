import Foundation

/// Checks a proof photo with OpenAI's Decisions API: each check is a
/// `predicate` question, and the API returns the probability it's true.
/// Cheaper than the Responses API (no output tokens) and reported to be
/// much faster, but there's no written reason.
struct DecisionsVerifier: WakeVerifier {
    /// The Decisions API only supports this model.
    static let model = "gpt-6-luna"

    var apiKey: String?
    var endpoint = URL(string: "https://api.openai.com/v1/decisions")!
    var session: URLSession = .shared

    func verify(_ request: VerificationRequest) async throws -> Verdict {
        guard let apiKey, !apiKey.isEmpty else { throw VerifierError.missingAPIKey }
        let (data, status) = try await OpenAIHTTP.post(
            Self.body(for: request), to: endpoint, apiKey: apiKey, session: session
        )
        return try Self.parse(data: data, status: status)
    }

    // MARK: Request

    static func body(for request: VerificationRequest) -> [String: Any] {
        var content: [[String: Any]] = [
            ["type": "input_text", "text": VerifierPrompt.userText(for: request)],
        ]
        for (index, photo) in request.referencePhotos.enumerated() {
            content.append(["type": "input_text", "text": "Reference photo \(index + 1) of \(request.referencePhotos.count):"])
            content.append(OpenAIHTTP.imagePart(photo))
        }
        content.append(["type": "input_text", "text": "New photo, taken just now with the in-app camera:"])
        content.append(OpenAIHTTP.imagePart(request.photo))

        return [
            "model": model,
            "input": [
                ["role": "developer", "content": [["type": "input_text", "text": VerifierPrompt.decisionsContext]]],
                ["role": "user", "content": content],
            ],
            "questions": ProofCheck.allCases.map { check in
                [
                    "type": "predicate",
                    "name": check.rawValue,
                    "instructions": VerifierPrompt.question(for: check, request: request),
                ] as [String: Any]
            },
        ]
    }

    // MARK: Response

    static func parse(data: Data, status: Int) throws -> Verdict {
        let json = try OpenAIHTTP.json(from: data, status: status)
        let answers = json["answers"] as? [[String: Any]] ?? []

        if let refusal = answers.first(where: { $0["type"] as? String == "refusal" }) {
            let message = refusal["refusal"] as? String
                ?? refusal["message"] as? String
                ?? "No reason given."
            throw VerifierError.refused(message)
        }

        var probabilities: [ProofCheck: Double] = [:]
        for answer in answers where answer["type"] as? String == "predicate" {
            guard let name = answer["name"] as? String,
                  let check = ProofCheck(rawValue: name),
                  let probability = (answer["probability"] as? NSNumber)?.doubleValue
            else { continue }
            probabilities[check] = min(max(probability, 0), 1)
        }
        // Every check must have an answer; a partial reply can't be trusted.
        guard probabilities.count == ProofCheck.allCases.count else {
            throw VerifierError.unreadableResponse
        }
        return Verdict(probabilities: probabilities, reason: nil)
    }
}
