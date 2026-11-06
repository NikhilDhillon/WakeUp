import Foundation
import Testing
@testable import WakeUp

struct WakeStateTests {
    private let alarmID = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func chain(
        kind: ScheduledChain.Kind = .main, startingIn offset: TimeInterval = -60, slots: Int = 3, alarm: UUID? = nil
    ) -> ScheduledChain {
        ScheduledChain(
            id: UUID(), alarmID: alarm ?? alarmID, kind: kind, day: now.addingTimeInterval(-3600),
            start: now.addingTimeInterval(offset), interval: 180,
            slotIDs: (0..<slots).map { _ in UUID() }, timeZoneID: "UTC", signature: "x"
        )
    }

    @Test func startsIdle() {
        let state = WakeState()
        #expect(state.phase == .idle)
        #expect(!state.isAwaitingProof)
    }

    @Test func aStartedChainStartsTheRinging() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        #expect(state.phase == .ringing)
        #expect(state.alarmID == alarmID)
        #expect(state.challenge != nil)
        #expect(state.isAwaitingProof)
    }

    @Test func aFutureChainDoesNothing() {
        var state = WakeState()
        state.sync(chains: [chain(startingIn: 600)], now: now)
        #expect(state.phase == .idle)
    }

    @Test func challengeStaysTheSameAcrossSyncsAndFailedTries() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        let challenge = state.challenge
        state.proofFailed()
        state.sync(chains: [chain()], now: now.addingTimeInterval(30))
        #expect(state.challenge == challenge)
        #expect(state.attempts == 1)
    }

    @Test func passingWithAFollowUpWaits() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        let delay = state.proofPassed(at: now, followUpDelay: 720, offline: false)
        #expect(delay == 720)
        #expect(state.phase == .passed)
        #expect(state.followUpAt == now.addingTimeInterval(720))
        #expect(!state.isAwaitingProof)
    }

    @Test func passingWithoutAFollowUpEndsTheMorning() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.proofPassed(at: now, followUpDelay: 0, offline: false)
        #expect(state.phase == .done)
        #expect(state.lastOutcome == .stayedUp)
    }

    @Test func anOfflinePassAlwaysGetsAFollowUp() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        let delay = state.proofPassed(at: now, followUpDelay: 0, offline: true)
        #expect(delay == AlarmSpec.offlineFollowUpDelay)
        #expect(state.phase == .passed)
        #expect(state.checkedOffline)
    }

    @Test func followUpRingsWithADifferentChallenge() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        let first = state.challenge
        state.proofPassed(at: now, followUpDelay: 720, offline: false)

        let later = now.addingTimeInterval(800)
        let followUp = chain(kind: .followUp, startingIn: -20)
        // Waiting: the follow-up hasn't started yet.
        var waiting = state
        waiting.sync(chains: [chain(kind: .followUp, startingIn: 600)], now: now.addingTimeInterval(60))
        #expect(waiting.phase == .passed)

        state.sync(chains: [followUp], now: later)
        #expect(state.phase == .followUpRinging)
        #expect(state.challenge != first)
        #expect(state.isAwaitingProof)
    }

    @Test func passingTheFollowUpFinishesTheMorning() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.proofPassed(at: now, followUpDelay: 720, offline: false)
        state.sync(chains: [chain(kind: .followUp, startingIn: -20)], now: now.addingTimeInterval(800))
        state.proofPassed(at: now.addingTimeInterval(820), followUpDelay: 720, offline: false)
        #expect(state.phase == .done)
        #expect(state.lastOutcome == .stayedUp)
    }

    @Test func ignoringTheWholeFollowUpIsWentBackToBed() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.proofPassed(at: now, followUpDelay: 720, offline: false)
        state.sync(chains: [chain(kind: .followUp, startingIn: -20)], now: now.addingTimeInterval(800))
        // The chain ran out and was cleaned up.
        state.sync(chains: [], now: now.addingTimeInterval(800 + 4 * 3600))
        #expect(state.phase == .idle)
        #expect(state.lastOutcome == .wentBackToBed)
    }

    @Test func aChainThatRangOutUnansweredIsMissed() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.sync(chains: [], now: now.addingTimeInterval(4 * 3600))
        #expect(state.phase == .idle)
        #expect(state.lastOutcome == .missed)
    }

    @Test func stoppingWithoutProofFinishesTheMorning() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.stoppedWithoutProof()
        #expect(state.phase == .done)
        #expect(state.lastOutcome == .stoppedWithoutProof)
    }

    @Test func tomorrowStartsANewMorning() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.proofPassed(at: now, followUpDelay: 0, offline: false)
        #expect(state.phase == .done)

        let tomorrow = now.addingTimeInterval(86_400)
        state.sync(chains: [chain(startingIn: 86_400 - 60)], now: tomorrow)
        #expect(state.phase == .ringing)
        #expect(state.attempts == 0)
        #expect(state.passedAt == nil)
    }

    @Test func aSecondAlarmCanStartWhileAFollowUpWaits() {
        var state = WakeState()
        let other = UUID()
        state.sync(chains: [chain()], now: now)
        state.proofPassed(at: now, followUpDelay: 3600, offline: false)
        state.sync(chains: [chain(kind: .followUp, startingIn: 3000), chain(startingIn: -10, alarm: other)], now: now.addingTimeInterval(60))
        #expect(state.phase == .ringing)
        #expect(state.alarmID == other)
    }

    @Test func survivesBeingSavedAndLoaded() {
        let defaults = UserDefaults(suiteName: "WakeStateTests-\(UUID().uuidString)")!
        let store = WakeStateStore(defaults: defaults)
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.proofFailed()
        store.save(state)
        #expect(store.load() == state)
    }

    @Test func aLostStateStillCatchesARingingFollowUp() {
        var state = WakeState()
        state.sync(chains: [chain(kind: .followUp, startingIn: -20)], now: now)
        #expect(state.phase == .followUpRinging)
    }

    @Test func challengeIsNeverRepeatedWhenExcluded() {
        for challenge in Challenge.allCases {
            for _ in 0..<20 { #expect(Challenge.random(excluding: challenge) != challenge) }
        }
    }
}
