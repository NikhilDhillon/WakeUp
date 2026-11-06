import Foundation

/// Sending requests to OpenAI and turning HTTP errors into friendly ones.
/// Shared by both verifiers.
enum OpenAIHTTP {
    /// A check should answer well within this; longer and the offline
    /// backup takes over (after one retry).
    static let requestTimeout: TimeInterval = 20

    static func post(
        _ body: [String: Any], to url: URL, apiKey: String, session: URLSession,
        timeout: TimeInterval = requestTimeout
    ) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw VerifierError.network(error.localizedDescription)
        }
    }

    /// Throws for any non-2xx status; otherwise returns the JSON object.
    static func json(from data: Data, status: Int) throws -> [String: Any] {
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
        return json
    }

    /// Input tokens OpenAI says it billed, if the reply includes usage.
    static func inputTokens(in json: [String: Any]) -> Int? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        return (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int)
    }

    static func imagePart(_ data: Data) -> [String: Any] {
        [
            "type": "input_image",
            "image_url": "data:image/jpeg;base64,\(data.base64EncodedString())",
            "detail": "auto",
        ]
    }
}
