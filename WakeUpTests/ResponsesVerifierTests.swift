import Foundation
import Testing
@testable import WakeUp

@Suite(.serialized)
struct ResponsesVerifierTests {
    private let request = VerificationRequest(
        photo: Data([1, 2, 3]),
        referencePhotos: [Data([4]), Data([5]), Data([6])],
        description: "Me sitting in the washroom with the light on",
        challenge: "Hold up 3 fingers",
        capturedAt: Date(timeIntervalSince1970: 0)
    )

    private static let goodVerdictText = #"{"same_place":true,"person_present":true,"matches_description":true,"challenge_completed":true,"appears_awake":true,"looks_like_photo_of_screen_or_print":false,"confidence":0.91,"reason":"You're in the washroom holding up 3 fingers."}"#

    private static func successBody(text: String = goodVerdictText) -> Data {
        let response: [String: Any] = [
            "id": "resp_1",
            "status": "completed",
            "output": [
                ["type": "reasoning", "summary": []],
                ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: response)
    }

    // MARK: Request body

    @Test func bodyHasInstructionsSchemaAndAllImages() throws {
        let body = ResponsesVerifier.body(for: request, model: "gpt-6-luna")
        #expect(body["model"] as? String == "gpt-6-luna")
        #expect(body["instructions"] as? String == VerifierPrompt.instructions)
        #expect(body["store"] as? Bool == false)

        let input = try #require(body["input"] as? [[String: Any]])
        let content = try #require(input.first?["content"] as? [[String: Any]])
        let images = content.filter { $0["type"] as? String == "input_image" }
        #expect(images.count == 4) // 3 references + the new photo
        #expect((images.last?["image_url"] as? String) == "data:image/jpeg;base64,AQID")

        let firstText = try #require(content.first?["text"] as? String)
        #expect(firstText.contains("Hold up 3 fingers"))
        #expect(firstText.contains("washroom"))

        let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)
        #expect(format["name"] as? String == "wake_verdict")
    }

    @Test func schemaRequiresEveryVerdictField() throws {
        let schema = VerifierPrompt.schema
        let properties = try #require(schema["properties"] as? [String: Any])
        let required = try #require(schema["required"] as? [String])
        #expect(Set(properties.keys) == Set(required))
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(required.count == 8)
    }

    @Test func reasoningEffortOnlyForReasoningModels() {
        let luna = ResponsesVerifier.body(for: request, model: "gpt-6-luna")
        #expect((luna["reasoning"] as? [String: String])?["effort"] == "low")
        let old = ResponsesVerifier.body(for: request, model: "gpt-4o-mini")
        #expect(old["reasoning"] == nil)
    }

    // MARK: Parsing

    @Test func parsesVerdictAfterReasoningItem() throws {
        let verdict = try ResponsesVerifier.parse(data: Self.successBody(), status: 200)
        #expect(verdict.probabilities[.challengeCompleted] == 0.91)
        #expect(verdict.reason == "You're in the washroom holding up 3 fingers.")
        #expect(verdict.passes(threshold: 0.7))
    }

    @Test func noAnswersBecomeLowProbabilities() throws {
        let text = #"{"same_place":true,"person_present":false,"matches_description":true,"challenge_completed":true,"appears_awake":true,"looks_like_photo_of_screen_or_print":false,"confidence":0.8,"reason":"No one is in the photo."}"#
        let verdict = try ResponsesVerifier.parse(data: Self.successBody(text: text), status: 200)
        #expect(abs(verdict.confidence(.personPresent) - 0.2) < 0.0001)
        #expect(abs(verdict.confidence(.screenOrPrint) - 0.8) < 0.0001)
        #expect(verdict.problems(threshold: 0.7) == [ProofCheck.personPresent.problem])
    }

    @Test func refusalBecomesRefusedError() {
        let body: [String: Any] = [
            "status": "completed",
            "output": [["type": "message", "content": [["type": "refusal", "refusal": "Can't help with that."]]]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: body)
        #expect(throws: VerifierError.refused("Can't help with that.")) {
            try ResponsesVerifier.parse(data: data, status: 200)
        }
    }

    @Test func incompleteResponseIsReported() {
        let body: [String: Any] = ["status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"], "output": []]
        let data = try! JSONSerialization.data(withJSONObject: body)
        #expect(throws: VerifierError.incomplete("max_output_tokens")) {
            try ResponsesVerifier.parse(data: data, status: 200)
        }
    }

    @Test func httpErrorsMapToFriendlyErrors() {
        let error = Data(#"{"error":{"message":"You exceeded your current quota."}}"#.utf8)
        #expect(throws: VerifierError.invalidAPIKey) { try ResponsesVerifier.parse(data: error, status: 401) }
        #expect(throws: VerifierError.rateLimited("You exceeded your current quota.")) {
            try ResponsesVerifier.parse(data: error, status: 429)
        }
        #expect(throws: VerifierError.server(503)) { try ResponsesVerifier.parse(data: error, status: 503) }
    }

    @Test func malformedVerdictTextIsUnreadable() {
        #expect(throws: VerifierError.unreadableResponse) {
            try ResponsesVerifier.parse(data: Self.successBody(text: "not json"), status: 200)
        }
    }

    // MARK: Network

    @Test func missingKeyFailsBeforeAnyRequest() async {
        let verifier = ResponsesVerifier(apiKey: nil, model: "gpt-6-luna")
        await #expect(throws: VerifierError.missingAPIKey) {
            try await verifier.verify(request)
        }
    }

    @Test func sendsAuthorizedPostAndReturnsVerdict() async throws {
        StubURLProtocol.setHandler(for: "/v1/responses") { urlRequest in
            #expect(urlRequest.httpMethod == "POST")
            #expect(urlRequest.url?.absoluteString == "https://api.openai.com/v1/responses")
            #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            return (200, Self.successBody())
        }
        defer { StubURLProtocol.setHandler(for: "/v1/responses", nil) }

        let verifier = ResponsesVerifier(apiKey: "test-key", model: "gpt-6-luna", session: StubURLProtocol.session())
        let verdict = try await verifier.verify(request)
        #expect(verdict.reason?.contains("3 fingers") == true)
    }
}

