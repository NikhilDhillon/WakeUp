import Foundation
import Testing
@testable import WakeUp

struct VerdictTests {
    private func verdict(_ overrides: [ProofCheck: Double] = [:]) -> Verdict {
        var probabilities: [ProofCheck: Double] = [
            .samePlace: 0.95, .personPresent: 0.97, .matchesDescription: 0.9,
            .challengeCompleted: 0.9, .appearsAwake: 0.92, .screenOrPrint: 0.02,
        ]
        probabilities.merge(overrides) { $1 }
        return Verdict(probabilities: probabilities, reason: nil)
    }

    @Test func goodPhotoPassesAtEveryStrictness() {
        for level in Strictness.allCases {
            #expect(verdict().passes(threshold: level.threshold))
        }
    }

    @Test func eachCheckMustReachTheThreshold() {
        let v = verdict([.challengeCompleted: 0.6])
        #expect(v.passes(threshold: Strictness.lenient.threshold))
        #expect(!v.passes(threshold: Strictness.normal.threshold))
        #expect(v.problems(threshold: 0.7) == [ProofCheck.challengeCompleted.problem])
    }

    @Test func screenCheckIsInverted() {
        // 30% chance it's a screen means 70% sure it isn't.
        let v = verdict([.screenOrPrint: 0.3])
        #expect(v.confidence(.screenOrPrint) == 0.7)
        #expect(v.passes(threshold: 0.7))
        #expect(!v.passes(threshold: 0.85))
        #expect(verdict([.screenOrPrint: 0.9]).problems(threshold: 0.5) == [ProofCheck.screenOrPrint.problem])
    }

    @Test func missingAnswerNeverPasses() {
        var v = verdict()
        v.probabilities[.personPresent] = nil
        #expect(v.confidence(.personPresent) == 0)
        #expect(!v.passes(threshold: 0.5))
    }

    @Test func listsEveryFailedCheckInOrder() {
        let v = verdict([.samePlace: 0.1, .personPresent: 0.2, .challengeCompleted: 0.3])
        #expect(v.problems(threshold: 0.7) == [
            ProofCheck.samePlace.problem, ProofCheck.personPresent.problem, ProofCheck.challengeCompleted.problem,
        ])
    }

    @Test func overallConfidenceIsTheWeakestCheck() {
        #expect(verdict([.appearsAwake: 0.55]).overallConfidence == 0.55)
        #expect(verdict([.screenOrPrint: 0.4]).overallConfidence == 0.6)
    }
}
