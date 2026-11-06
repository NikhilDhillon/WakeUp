import Foundation
import Testing
@testable import WakeUp

struct VerdictTests {
    private func verdict(
        samePlace: Bool = true,
        personPresent: Bool = true,
        matchesDescription: Bool = true,
        challengeCompleted: Bool = true,
        appearsAwake: Bool = true,
        screen: Bool = false,
        confidence: Double = 0.9
    ) -> Verdict {
        Verdict(
            samePlace: samePlace,
            personPresent: personPresent,
            matchesDescription: matchesDescription,
            challengeCompleted: challengeCompleted,
            appearsAwake: appearsAwake,
            looksLikePhotoOfScreenOrPrint: screen,
            confidence: confidence,
            reason: "test"
        )
    }

    @Test func goodPhotoPassesAtEveryStrictness() {
        for level in Strictness.allCases {
            #expect(verdict().passes(threshold: level.threshold))
        }
    }

    @Test func confidenceBelowThresholdFails() {
        let v = verdict(confidence: 0.6)
        #expect(v.passes(threshold: Strictness.lenient.threshold))
        #expect(!v.passes(threshold: Strictness.normal.threshold))
        #expect(v.problems(threshold: 0.7) == ["The AI wasn't sure enough (60%, needs 70%)."])
    }

    @Test func screenPhotoFailsEvenWhenConfident() {
        let v = verdict(screen: true, confidence: 0.99)
        #expect(!v.passes(threshold: 0.5))
        #expect(v.problems(threshold: 0.5) == ["This looks like a photo of a screen or a printout."])
    }

    @Test func listsEveryFailedCheck() {
        let v = verdict(samePlace: false, personPresent: false, challengeCompleted: false)
        #expect(v.problems(threshold: 0.7).count == 3)
    }

    @Test func decodesSnakeCaseJSON() throws {
        let json = """
        {"same_place":true,"person_present":true,"matches_description":false,
         "challenge_completed":true,"appears_awake":true,
         "looks_like_photo_of_screen_or_print":false,"confidence":0.8,"reason":"Close."}
        """
        let v = try JSONDecoder().decode(Verdict.self, from: Data(json.utf8))
        #expect(v.matchesDescription == false)
        #expect(v.confidence == 0.8)
        #expect(v.reason == "Close.")
    }
}
