import Foundation
import Testing
@testable import WakeUp

@Suite(.serialized)
struct DecisionsVerifierTests {
    private let request = VerificationRequest(
        photo: Data([1, 2, 3]),
        referencePhotos: [Data([4]), Data([5]), Data([6])],
        description: "Me sitting in the washroom with the light on",
        challenge: "Hold up 3 fingers",
        capturedAt: Date(timeIntervalSince1970: 0)
    )

    private static func answers(_ probabilities: [ProofCheck: Double]) -> Data {
        let body: [String: Any] = [
            "answers": probabilities.map { ["type": "predicate", "name": $0.key.rawValue, "probability": $0.value] },
            "usage": ["input_tokens": 4200],
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private static let allGood: [ProofCheck: Double] = [
        .samePlace: 0.96, .personPresent: 0.99, .matchesDescription: 0.9,
        .challengeCompleted: 0.87, .appearsAwake: 0.93, .screenOrPrint: 0.04,
    ]

    // MARK: Request body

    @Test func bodyAsksOnePredicatePerCheck() throws {
        let body = DecisionsVerifier.body(for: request)
        #expect(body["model"] as? String == "gpt-6-luna")

        let questions = try #require(body["questions"] as? [[String: Any]])
        #expect(questions.count == ProofCheck.allCases.count)
        #expect(questions.allSatisfy { $0["type"] as? String == "predicate" })
        let names = questions.compactMap { $0["name"] as? String }
        #expect(Set(names) == Set(ProofCheck.allCases.map(\.rawValue)))
        #expect(Set(names).count == names.count) // names must be unique

        let challenge = try #require(questions.first { $0["name"] as? String == "challenge_completed" })
        #expect((challenge["instructions"] as? String)?.contains("Hold up 3 fingers") == true)
        let description = try #require(questions.first { $0["name"] as? String == "matches_description" })
        #expect((description["instructions"] as? String)?.contains("washroom") == true)
    }

    @Test func bodySendsContextThenAllPhotos() throws {
        let body = DecisionsVerifier.body(for: request)
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.map { $0["role"] as? String } == ["developer", "user"])

        let developer = try #require(input[0]["content"] as? [[String: Any]])
        #expect(developer.allSatisfy { $0["type"] as? String == "input_text" })

        let content = try #require(input[1]["content"] as? [[String: Any]])
        let images = content.filter { $0["type"] as? String == "input_image" }
        #expect(images.count == 4) // 3 references + the new photo
        #expect(images.last?["image_url"] as? String == "data:image/jpeg;base64,AQID")
        // Only fields the Decisions guide documents.
        #expect(Set(body.keys) == ["model", "input", "questions"])
    }

    // MARK: Parsing

    @Test func parsesProbabilitiesIntoVerdict() throws {
        let verdict = try DecisionsVerifier.parse(data: Self.answers(Self.allGood), status: 200)
        #expect(verdict.probabilities[.challengeCompleted] == 0.87)
        #expect(verdict.reason == nil)
        #expect(verdict.passes(threshold: Strictness.strict.threshold))
    }

    @Test func lowProbabilityFails() throws {
        var probabilities = Self.allGood
        probabilities[.personPresent] = 0.12
        let verdict = try DecisionsVerifier.parse(data: Self.answers(probabilities), status: 200)
        #expect(verdict.problems(threshold: 0.7) == [ProofCheck.personPresent.problem])
    }

    @Test func missingAnswerIsUnreadable() {
        var probabilities = Self.allGood
        probabilities[.appearsAwake] = nil
        #expect(throws: VerifierError.unreadableResponse) {
            try DecisionsVerifier.parse(data: Self.answers(probabilities), status: 200)
        }
    }

    @Test func refusalBecomesRefusedError() {
        let body: [String: Any] = ["answers": [["type": "refusal", "name": "same_place", "refusal": "Can't help with that."]]]
        let data = try! JSONSerialization.data(withJSONObject: body)
        #expect(throws: VerifierError.refused("Can't help with that.")) {
            try DecisionsVerifier.parse(data: data, status: 200)
        }
    }

    @Test func httpErrorsMapToFriendlyErrors() {
        let error = Data(#"{"error":{"message":"Invalid image."}}"#.utf8)
        #expect(throws: VerifierError.invalidAPIKey) { try DecisionsVerifier.parse(data: error, status: 401) }
        #expect(throws: VerifierError.badRequest("Invalid image.")) { try DecisionsVerifier.parse(data: error, status: 400) }
        #expect(throws: VerifierError.server(500)) { try DecisionsVerifier.parse(data: error, status: 500) }
    }

    // MARK: Network

    @Test func missingKeyFailsBeforeAnyRequest() async {
        await #expect(throws: VerifierError.missingAPIKey) {
            try await DecisionsVerifier(apiKey: "").verify(request)
        }
    }

    @Test func postsToDecisionsEndpoint() async throws {
        StubURLProtocol.setHandler(for: "/v1/decisions") { urlRequest in
            #expect(urlRequest.httpMethod == "POST")
            #expect(urlRequest.url?.absoluteString == "https://api.openai.com/v1/decisions")
            #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            return (200, Self.answers(Self.allGood))
        }
        defer { StubURLProtocol.setHandler(for: "/v1/decisions", nil) }

        let verifier = DecisionsVerifier(apiKey: "test-key", session: StubURLProtocol.session())
        let verdict = try await verifier.verify(request)
        #expect(verdict.passes(threshold: 0.85))
    }
}
