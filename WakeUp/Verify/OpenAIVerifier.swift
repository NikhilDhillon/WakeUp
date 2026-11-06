import Foundation

/// Checks a proof photo with OpenAI's Responses API, asking for a reply
/// that must match the `Verdict` JSON schema.
struct OpenAIVerifier: WakeVerifier {
    var apiKey: String?
    var model: String
    var endpoint = URL(string: "https://api.openai.com/v1/responses")!
    var session: URLSession = .shared

    func verify(_ request: VerificationRequest) async throws -> Verdict {
        guard let apiKey, !apiKey.isEmpty else { throw VerifierError.missingAPIKey }

        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 60)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: Self.body(for: request, model: model))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw VerifierError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parse(data: data, status: status)
    }

    // MARK: Request

    static func body(for request: VerificationRequest, model: String) -> [String: Any] {
        var content: [[String: Any]] = [
            ["type": "input_text", "text": VerifierPrompt.userText(for: request)],
        ]
        for (index, photo) in request.referencePhotos.enumerated() {
            content.append(["type": "input_text", "text": "Reference photo \(index + 1) of \(request.referencePhotos.count):"])
            content.append(image(photo))
        }
        content.append(["type": "input_text", "text": "New photo, taken just now with the in-app camera:"])
        content.append(image(request.photo))

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

    private static func image(_ data: Data) -> [String: Any] {
        [
            "type": "input_image",
            "image_url": "data:image/jpeg;base64,\(data.base64EncodedString())",
            "detail": "auto",
        ]
    }

    // MARK: Response

    static func parse(data: Data, status: Int) throws -> Verdict {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200..<300).contains(status) else {
            let error = json?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "Unknown error."
            switch status {
            case 401: throw VerifierError.invalidAPIKey
            case 429: throw VerifierError.rateLimited(message)
            case 400..<500: throw VerifierError.badRequest(message)
            default: throw VerifierError.server(status)
            }
        }
        guard let json else { throw VerifierError.unreadableResponse }

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
                          let verdict = try? JSONDecoder().decode(Verdict.self, from: Data(text.utf8))
                    else { throw VerifierError.unreadableResponse }
                    return verdict
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
