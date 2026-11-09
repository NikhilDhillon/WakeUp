import Foundation
import Testing
@testable import WakeUp

struct NapTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func nap(
        minutes: Int = 20, snoozes: Int = 2, snoozeMinutes: Int = 10, followUp: Int = 0, proof: String = "Desk"
    ) -> NapSession {
        NapSession.make(
            now: now, minutes: minutes, missionID: nil, proofName: proof, chainLength: 10,
            chainIntervalMinutes: 3, followUpMinutes: followUp, snoozes: snoozes, snoozeMinutes: snoozeMinutes
        )
    }

    private func chain(
        kind: ScheduledChain.Kind = .nap, alarm: UUID, startingIn offset: TimeInterval, slots: Int = 3,
        signature: String = NapSession.signature
    ) -> ScheduledChain {
        ScheduledChain(
            id: UUID(), alarmID: alarm, kind: kind, day: now, start: now.addingTimeInterval(offset),
            interval: 180, slotIDs: (0..<slots).map { _ in UUID() }, timeZoneID: "UTC", signature: signature
        )
    }

    // MARK: The nap

    @Test func ringsAtNowPlusTheDuration() {
        let nap = nap(minutes: 20)
        #expect(nap.ringsAt == now.addingTimeInterval(20 * 60))
        #expect(nap.duration == 20 * 60)
        #expect(nap.snoozesLeft == 2)
    }

    @Test func aNapIsBetweenFiveMinutesAndThreeHours() {
        #expect(nap(minutes: 1).duration == 5 * 60)
        #expect(nap(minutes: 500).duration == 180 * 60)
        #expect(nap(minutes: 5).duration == 5 * 60)
        #expect(nap(minutes: 180).duration == 180 * 60)
    }

    @Test func theQuickNapMayBeShort() {
        let quick = NapSession.make(
            now: now, minutes: 1, missionID: nil, proofName: "", chainLength: 3, chainIntervalMinutes: 1,
            followUpMinutes: 0, snoozes: 2, snoozeMinutes: 1, allowShort: true
        )
        #expect(quick.duration == 60)
    }

    @Test func snoozesAreHeldToZeroThroughThree() {
        #expect(nap(snoozes: 9).snoozesAllowed == 3)
        #expect(nap(snoozes: -1).snoozesAllowed == 0)
    }

    @Test func survivesBeingEncodedAndDecoded() throws {
        var original = nap(followUp: 10)
        original.snoozesUsed = 1
        original.hasRung = true
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(NapSession.self, from: data) == original)
    }

    @Test func aNapSavedWithoutNewerFieldsStillLoads() throws {
        let json = """
        {"id":"\(UUID().uuidString)","startedAt":0,"ringsAt":1200,"duration":1200,"chainLength":5,
         "chainInterval":180,"followUpDelay":0,"snoozesAllowed":2,"snoozeLength":600}
        """
        let decoded = try JSONDecoder().decode(NapSession.self, from: Data(json.utf8))
        #expect(decoded.snoozesUsed == 0)
        #expect(!decoded.hasRung)
        #expect(decoded.passedAt == nil)
        #expect(decoded.proofName == "")
    }

    // MARK: Cancel

    @Test func cancelIsAllowedOnlyBeforeTheFirstRing() {
        let nap = nap()
        #expect(nap.canCancel(at: now))
        #expect(!nap.canCancel(at: nap.ringsAt))
        #expect(!nap.canCancel(at: nap.ringsAt.addingTimeInterval(5)))
    }

    @Test func cancelIsRefusedOnceTheNapHasRung() {
        var nap = nap()
        nap.hasRung = true
        #expect(!nap.canCancel(at: now))
    }

    @Test func cancelStaysLockedAfterASnoozeEvenThoughItRingsLater() {
        let snoozed = nap().snoozed(at: now.addingTimeInterval(25 * 60))
        #expect(snoozed != nil)
        #expect(snoozed?.canCancel(at: now.addingTimeInterval(26 * 60)) == false)
    }

    // MARK: Snooze

    @Test func aSnoozeMovesTheRingToNowPlusTheSnoozeLength() {
        let later = now.addingTimeInterval(21 * 60)
        let snoozed = nap(snoozeMinutes: 10).snoozed(at: later)
        #expect(snoozed?.ringsAt == later.addingTimeInterval(600))
        #expect(snoozed?.snoozesUsed == 1)
        #expect(snoozed?.snoozesLeft == 1)
        #expect(snoozed?.hasRung == true)
    }

    @Test func snoozesNeverGoPastTheLimit() {
        var current = nap(snoozes: 2)
        var count = 0
        while let next = current.snoozed(at: now) {
            current = next
            count += 1
            #expect(count <= 2)
        }
        #expect(count == 2)
        #expect(current.snoozesUsed == 2)
        #expect(current.snoozesLeft == 0)
        #expect(current.usedAllSnoozes)
        #expect(current.snoozed(at: now) == nil)
    }

    @Test func aNapWithNoSnoozesNeverSnoozesAndIsNotToldItRanOut() {
        let none = nap(snoozes: 0)
        #expect(none.snoozed(at: now) == nil)
        #expect(!none.usedAllSnoozes)
    }

    @Test func aPassedNapDoesNotSnooze() {
        var done = nap()
        done.passedAt = now
        #expect(done.snoozed(at: now) == nil)
    }

    // MARK: Stages and text

    @Test func stagesFollowTheClock() {
        let nap = nap()
        #expect(nap.stage(at: now) == .waiting)
        #expect(nap.stage(at: nap.ringsAt.addingTimeInterval(1)) == .ringing)
        let snoozed = nap.snoozed(at: nap.ringsAt)!
        #expect(snoozed.stage(at: nap.ringsAt.addingTimeInterval(60)) == .snoozed)
        #expect(snoozed.stage(at: snoozed.ringsAt.addingTimeInterval(1)) == .ringing)
        var done = snoozed
        done.passedAt = now
        #expect(done.stage(at: now) == .done)
    }

    @Test func countdownReadsLikeATimer() {
        let ring = now.addingTimeInterval(19 * 60 + 42)
        #expect(NapSession.countdownText(from: now, to: ring) == "19:42")
        #expect(NapSession.countdownText(from: now, to: now.addingTimeInterval(3600 + 5 * 60 + 9)) == "1:05:09")
        #expect(NapSession.countdownText(from: now, to: now.addingTimeInterval(-30)) == "0:00")
    }

    @Test func snoozesLeftText() {
        var nap = nap(snoozes: 3)
        #expect(nap.snoozesLeftText == "3 snoozes left")
        nap.snoozesUsed = 2
        #expect(nap.snoozesLeftText == "1 snooze left")
        nap.snoozesUsed = 3
        #expect(nap.snoozesLeftText == "No snoozes left")
    }

    @Test func theStatusPillTextTellsNappingFromSnoozed() {
        let nap = nap()
        #expect(nap.statusText(at: now).hasPrefix("Napping until"))
        let snoozed = nap.snoozed(at: nap.ringsAt)!
        #expect(snoozed.statusText(at: nap.ringsAt.addingTimeInterval(1)).hasPrefix("Snoozed until"))
        #expect(nap.statusText(at: nap.ringsAt.addingTimeInterval(1)) == "Nap's over")
    }

    // MARK: Ring settings

    @Test func ringSettingsLookInTheNapBeforeTheSpec() {
        var nap = nap()
        nap.sound = AlarmSound.loud.rawValue
        let spec = AlarmSpec(
            id: nap.id, hour: 7, minute: 0, weekdays: .everyDay, missionID: nil, chainLength: 3,
            chainInterval: 600, followUpDelay: 0, isEnabled: true, skippedDays: [], sound: AlarmSound.standard.rawValue
        )
        let settings = RingSettings.resolve(alarmID: nap.id, nap: nap, spec: spec)
        #expect(settings == RingSettings(sound: AlarmSound.loud.rawValue, interval: 180))
    }

    @Test func ringSettingsFallBackToTheSpecForMornings() {
        let nap = nap()
        let spec = AlarmSpec(
            id: UUID(), hour: 7, minute: 0, weekdays: .everyDay, missionID: nil, chainLength: 3,
            chainInterval: 600, followUpDelay: 0, isEnabled: true, skippedDays: [], sound: AlarmSound.loud.rawValue
        )
        #expect(RingSettings.resolve(alarmID: spec.id, nap: nap, spec: spec)
                == RingSettings(sound: AlarmSound.loud.rawValue, interval: 600))
        #expect(RingSettings.resolve(alarmID: UUID(), nap: nap, spec: nil) == nil)
    }

    // MARK: Saved nap

    private func store() -> ScheduleStore {
        ScheduleStore(defaults: UserDefaults(suiteName: "NapTests-\(UUID().uuidString)")!)
    }

    @Test func theStoreKeepsOneNapAndForgetsIt() {
        let store = store()
        #expect(store.nap == nil)
        let nap = nap()
        store.nap = nap
        #expect(store.nap == nap)
        store.nap = nil
        #expect(store.nap == nil)
    }

    @Test func clearingTheChainsAlsoForgetsTheNap() {
        let store = store()
        store.nap = nap()
        store.clear()
        #expect(store.nap == nil)
    }

    @Test func theNapIsMarkedRungOnceItsChainStarts() {
        let store = store()
        let nap = nap()
        store.nap = nap
        store.add(chain(alarm: nap.id, startingIn: 600))
        #expect(store.markNapRungIfStarted(now: now)?.hasRung == false)
        #expect(store.markNapRungIfStarted(now: now.addingTimeInterval(601))?.hasRung == true)
        #expect(store.nap?.hasRung == true)
    }

    @Test func napRecordsAreKeptOldestFirstAndCapped() {
        let store = store()
        for index in 0..<(ScheduleStore.napRecordsKept + 5) {
            store.addNapRecord(NapRecord(
                id: UUID(), startedAt: now.addingTimeInterval(Double(index)), duration: 1200, snoozesUsed: 0, upAt: nil
            ))
        }
        #expect(store.napRecords.count == ScheduleStore.napRecordsKept)
        #expect(store.napRecords.first?.startedAt == now.addingTimeInterval(5))
        store.clearNapRecords()
        #expect(store.napRecords.isEmpty)
    }

    @Test func defaultsComeBackAsSaved() {
        let defaults = UserDefaults(suiteName: "NapTests-\(UUID().uuidString)")!
        #expect(NapDefaults.load(from: defaults) == NapDefaults())
        var saved = NapDefaults()
        saved.minutes = 45
        saved.snoozes = 1
        saved.save(to: defaults)
        #expect(NapDefaults.load(from: defaults) == saved)
        #expect(NapDefaults().minutes == 20)
        #expect(NapDefaults().snoozes == 2)
        #expect(NapDefaults().snoozeMinutes == 10)
    }

    // MARK: Chains

    @Test func aNapChainAndItsFollowUpBelongToTheNap() {
        let id = UUID()
        #expect(chain(alarm: id, startingIn: 0).belongsToNap)
        #expect(chain(kind: .followUp, alarm: id, startingIn: 0).belongsToNap)
        #expect(!chain(kind: .followUp, alarm: id, startingIn: 0, signature: "7:0|3|180|UTC|standard").belongsToNap)
        #expect(!chain(kind: .main, alarm: id, startingIn: 0, signature: "x").belongsToNap)
    }

    // MARK: Ring wording

    @Test func theFirstRingNamesTheProof() {
        #expect(RingNotice.alarmTitle(kind: .nap, index: 0, count: 10, next: nil, proof: "Desk")
                == "Nap's over: get to your desk")
        #expect(RingNotice.alarmTitle(kind: .nap, index: 0, count: 10, next: nil, proof: "Kitchen table")
                == "Nap's over: get to Kitchen table")
        #expect(RingNotice.alarmTitle(kind: .nap, index: 0, count: 10, next: nil, proof: nil)
                == "Nap's over: prove you're up")
    }

    @Test func laterRingsAskIfYouAreStillNapping() {
        #expect(RingNotice.alarmTitle(kind: .nap, index: 1, count: 10, next: nil, proof: "Desk")
                == "Still napping? (2 of 10)")
        #expect(RingNotice.alarmTitle(kind: .nap, index: 9, count: 10, next: nil, proof: "Desk")
                == "Last ring: only a photo stops it")
    }

    @Test func theFirstRingAfterTheLastSnoozeSaysSo() {
        #expect(RingNotice.alarmTitle(kind: .nap, index: 0, count: 10, next: nil, proof: "Desk", noSnoozesLeft: true)
                == "No snoozes left: only a photo stops it")
        // Only the first ring says it.
        #expect(RingNotice.alarmTitle(kind: .nap, index: 1, count: 10, next: nil, proof: "Desk", noSnoozesLeft: true)
                == "Still napping? (2 of 10)")
    }

    @Test func aMorningTitleIsUnchanged() {
        #expect(RingNotice.alarmTitle(kind: .main, index: 0, count: 10, next: nil) == "Time to prove you're up")
        #expect(RingNotice.alarmTitle(kind: .followUp, index: 0, count: 4, next: nil) == "Still up? Prove it again")
    }

    @Test func aNapFollowUpAsksAboutTheDesk() {
        #expect(RingNotice.alarmTitle(kind: .followUp, index: 0, count: 4, next: nil, proof: "Desk")
                == "Still at your desk? Prove it again")
        #expect(RingNotice.alarmTitle(kind: .followUp, index: 2, count: 4, next: nil, proof: "Desk")
                == "Still at your desk? (3 of 4)")
    }

    @Test func theSnoozeNoteSaysWhenAndHowManyAreLeft() {
        let time = now.formatted(date: .omitted, time: .shortened)
        let one = RingNotice.snoozeText(until: now, snoozesLeft: 1)
        #expect(one.title == "Snoozed until \(time)")
        #expect(one.body.hasPrefix("1 snooze left."))
        #expect(RingNotice.snoozeText(until: now, snoozesLeft: 0).body.hasPrefix("No snoozes left"))
        #expect(RingNotice.snoozeText(until: now, snoozesLeft: 2).body.hasPrefix("2 snoozes left."))
    }

    // MARK: Planner

    @Test func theNapChainIsLeftAloneByThePlanner() {
        let id = UUID()
        let waiting = chain(alarm: id, startingIn: 1200)
        let ringing = chain(alarm: id, startingIn: -60)
        let plan = SchedulePlanner.plan(specs: [], existing: [waiting, ringing], now: now)
        #expect(plan.cancel.isEmpty)
        #expect(plan.expire.isEmpty)
        #expect(plan.create.isEmpty)
    }

    @Test func aNapChainIsNotExpiredEarly() {
        let id = UUID()
        // Last ring was a minute ago: still owed.
        let recent = chain(alarm: id, startingIn: -600)
        #expect(SchedulePlanner.plan(specs: [], existing: [recent], now: now).expire.isEmpty)
        // Long gone.
        let old = chain(alarm: id, startingIn: -(ScheduledChain.owedGrace + 3600))
        #expect(SchedulePlanner.plan(specs: [], existing: [old], now: now).expire == [old])
    }

    @Test func aNapChainCountsTowardTheSlotBudget() {
        let spec = AlarmSpec(
            id: UUID(), hour: 7, minute: 0, weekdays: .everyDay, missionID: nil, chainLength: 3,
            chainInterval: 180, followUpDelay: 0, isEnabled: true, skippedDays: []
        )
        let calendar = Calendar(identifier: .gregorian)
        let withoutNap = SchedulePlanner.plan(specs: [spec], existing: [], now: now, slotBudget: 12, calendar: calendar)
        let napChain = chain(alarm: UUID(), startingIn: 1200, slots: 10)
        let withNap = SchedulePlanner.plan(specs: [spec], existing: [napChain], now: now, slotBudget: 12, calendar: calendar)
        #expect(withoutNap.create.count == 4)
        #expect(withNap.create.count == 0)
        #expect(withNap.cancel.isEmpty)
    }
}

struct NapWakeStateTests {
    private let napID = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func chain(
        kind: ScheduledChain.Kind = .nap, startingIn offset: TimeInterval = -60, alarm: UUID? = nil,
        signature: String = NapSession.signature
    ) -> ScheduledChain {
        ScheduledChain(
            id: UUID(), alarmID: alarm ?? napID, kind: kind, day: now, start: now.addingTimeInterval(offset),
            interval: 180, slotIDs: (0..<3).map { _ in UUID() }, timeZoneID: "UTC", signature: signature
        )
    }

    @Test func aRingingNapIsANapRinging() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        #expect(state.phase == .ringing)
        #expect(state.isNap)
        #expect(state.isAwaitingProof)
    }

    @Test func aMorningIsNotANap() {
        var state = WakeState()
        state.sync(chains: [chain(kind: .main, signature: "x")], now: now)
        #expect(state.phase == .ringing)
        #expect(!state.isNap)
    }

    @Test func aNapRingingThenAPassIsDone() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.proofPassed(at: now, followUpDelay: 0, offline: false)
        #expect(state.phase == .done)
        #expect(state.lastOutcome == .stayedUp)
        #expect(state.isNap)
    }

    @Test func aNapThatRangOutIsMissed() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.sync(chains: [], now: now.addingTimeInterval(4 * 3600))
        #expect(state.phase == .idle)
        #expect(state.lastOutcome == .missed)
        #expect(state.isNap)
    }

    @Test func aSnoozeGoesToSnoozedAndBack_NeverMissed() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        let challenge = state.challenge

        // Stop snoozed it: the old chain is gone and a new one waits.
        let waiting = chain(startingIn: 600)
        state.sync(chains: [waiting], now: now.addingTimeInterval(30))
        #expect(state.phase == .snoozed)
        #expect(!state.isAwaitingProof)
        #expect(state.lastOutcome != .missed)

        // Still waiting a while later.
        state.sync(chains: [waiting], now: now.addingTimeInterval(300))
        #expect(state.phase == .snoozed)

        // The new chain starts: same challenge, fresh tries.
        state.proofFailed()
        state.sync(chains: [chain(startingIn: -5)], now: now.addingTimeInterval(605))
        #expect(state.phase == .ringing)
        #expect(state.challenge == challenge)
        #expect(state.attempts == 0)
        #expect(state.isAwaitingProof)
    }

    @Test func aSnoozedNapWhoseChainVanishedIsMissed() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.sync(chains: [chain(startingIn: 600)], now: now.addingTimeInterval(30))
        #expect(state.phase == .snoozed)
        state.sync(chains: [], now: now.addingTimeInterval(8 * 3600))
        #expect(state.phase == .idle)
        #expect(state.lastOutcome == .missed)
    }

    @Test func aMorningRingingOutIsStillMissedNotSnoozed() {
        var state = WakeState()
        state.sync(chains: [chain(kind: .main, signature: "x", )], now: now)
        // A future nap chain for a different alarm doesn't turn a morning into a snooze.
        state.sync(chains: [chain(startingIn: 600)], now: now.addingTimeInterval(4 * 3600))
        #expect(state.phase == .idle)
        #expect(state.lastOutcome == .missed)
    }

    @Test func iAmUpEarlyOpensTheProofBeforeTheNapRings() {
        var state = WakeState()
        state.beginNapEarly(alarmID: napID, day: now)
        #expect(state.phase == .ringing)
        #expect(state.isNap)
        #expect(state.challenge != nil)
        #expect(state.isAwaitingProof)
        state.proofPassed(at: now, followUpDelay: 0, offline: false)
        #expect(state.phase == .done)
    }

    @Test func iAmUpEarlyWhileSnoozedKeepsTheChallenge() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.sync(chains: [chain(startingIn: 600)], now: now.addingTimeInterval(30))
        let challenge = state.challenge
        state.beginNapEarly(alarmID: napID, day: now)
        #expect(state.phase == .ringing)
        #expect(state.challenge == challenge)
    }

    @Test func dismissingTheEarlyProofReturnsToWaiting() {
        var state = WakeState()
        state.beginNapEarly(alarmID: napID, day: now)
        state.sync(chains: [chain(startingIn: 600)], now: now)
        #expect(state.phase == .snoozed)
        #expect(!state.isAwaitingProof)
    }

    @Test func aNapAndAMorningOverlapEarliestStartedWins() {
        var state = WakeState()
        let morning = chain(kind: .main, startingIn: -300, alarm: UUID(), signature: "x")
        let nap = chain(startingIn: -60)
        state.sync(chains: [nap, morning], now: now)
        #expect(state.phase == .ringing)
        #expect(state.alarmID == morning.alarmID)
        #expect(!state.isNap)

        var other = WakeState()
        other.sync(chains: [chain(startingIn: -300), chain(kind: .main, startingIn: -60, alarm: UUID(), signature: "x")], now: now)
        #expect(other.alarmID == napID)
        #expect(other.isNap)
    }

    @Test func theNapFollowUpIsANapFollowUp() {
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.proofPassed(at: now, followUpDelay: 600, offline: false)
        #expect(state.phase == .passed)
        state.sync(chains: [chain(kind: .followUp, startingIn: -20)], now: now.addingTimeInterval(700))
        #expect(state.phase == .followUpRinging)
        #expect(state.isNap)
        state.proofPassed(at: now.addingTimeInterval(720), followUpDelay: 600, offline: false)
        #expect(state.phase == .done)
    }

    @Test func survivesBeingSavedAndLoadedWhileSnoozed() {
        let defaults = UserDefaults(suiteName: "NapWakeStateTests-\(UUID().uuidString)")!
        let store = WakeStateStore(defaults: defaults)
        var state = WakeState()
        state.sync(chains: [chain()], now: now)
        state.sync(chains: [chain(startingIn: 600)], now: now.addingTimeInterval(30))
        store.save(state)
        #expect(store.load() == state)
        #expect(store.load().phase == .snoozed)
    }

    @Test func aStateSavedBeforeNapsStillLoads() {
        let defaults = UserDefaults(suiteName: "NapWakeStateTests-\(UUID().uuidString)")!
        defaults.set(Data(#"{"phase":"ringing","attempts":1,"checkedOffline":false}"#.utf8), forKey: "wake.state")
        let state = WakeStateStore(defaults: defaults).load()
        #expect(state.phase == .ringing)
        #expect(state.attempts == 1)
        #expect(!state.isNap)
    }
}

struct NapHistoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func info(_ kind: AttemptKind, passed: Bool = true, at offset: TimeInterval = 0) -> AttemptInfo {
        AttemptInfo(date: now.addingTimeInterval(offset), kind: kind, passed: passed)
    }

    @Test func napAttemptsDoNotMakeAMorning() {
        let summaries = HistoryMath.summaries(of: [info(.nap), info(.nap, passed: false, at: -60)])
        #expect(summaries.isEmpty)
    }

    @Test func napAttemptsDoNotChangeAMorningSummary() {
        let morning = [info(.wake, at: -7200)]
        let before = HistoryMath.summaries(of: morning)
        let after = HistoryMath.summaries(of: morning + [info(.nap), info(.nap, passed: false, at: -30)])
        #expect(before == after)
        #expect(after.first?.tries == 1)
        #expect(after.first?.followUpTries == 0)
    }

    @Test func napPassesDoNotChangeTheStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        // The pass days a view builds only count `.wake` passes.
        let attempts = [info(.wake, at: -86_400), info(.nap)]
        let passDays = Set(attempts.filter { $0.kind == .wake && $0.passed }.map(\.date))
        #expect(HistoryMath.streak(passDays: passDays, missedDays: [], now: now) == 1)
        #expect(HistoryMath.streak(passDays: passDays.union([now]), missedDays: [], now: now) == 2)
        _ = yesterday
    }

    @Test func aNapRowCountsItsOwnTries() {
        let record = NapRecord(
            id: UUID(), startedAt: now.addingTimeInterval(-1800), duration: 1200, snoozesUsed: 2,
            upAt: now
        )
        let attempts = [
            info(.nap, passed: false, at: -120), info(.nap, at: -30),
            // Before the nap began, and a morning photo: not this nap's.
            info(.nap, at: -4000), info(.wake, at: -90),
        ]
        let rows = HistoryMath.napSummaries(records: [record], attempts: attempts)
        #expect(rows.count == 1)
        #expect(rows[0].tries == 2)
        #expect(rows[0].minutes == 20)
        #expect(rows[0].snoozes == 2)
    }

    @Test func aLaterNapsPhotosAreNotCountedForAnEarlierOne() {
        let first = NapRecord(id: UUID(), startedAt: now.addingTimeInterval(-7200), duration: 1200, snoozesUsed: 0, upAt: nil)
        let second = NapRecord(id: UUID(), startedAt: now.addingTimeInterval(-3600), duration: 600, snoozesUsed: 1, upAt: now)
        let rows = HistoryMath.napSummaries(records: [second, first], attempts: [info(.nap, at: -3000)])
        #expect(rows.map(\.id) == [second.id, first.id])
        #expect(rows[0].tries == 1)
        #expect(rows[1].tries == 0)
    }

    @Test func theNapLineReadsLikeThePlan() {
        let up = now.addingTimeInterval(100)
        let line = HistoryMath.napLine(.init(
            id: UUID(), startedAt: now, minutes: 20, snoozes: 2, upAt: up, tries: 1
        ))
        let clock = up.formatted(.dateTime.hour().minute())
        #expect(line == "Nap · 20 min · snoozed twice · up at \(clock), 1 try")
    }

    @Test func theNapLineHandlesOtherCases() {
        #expect(HistoryMath.napLine(.init(id: UUID(), startedAt: now, minutes: 30, snoozes: 0, upAt: nil, tries: 0))
                == "Nap · 30 min · not up")
        let one = HistoryMath.napLine(.init(id: UUID(), startedAt: now, minutes: 10, snoozes: 1, upAt: nil, tries: 3))
        #expect(one == "Nap · 10 min · snoozed once · not up, 3 tries")
        let three = HistoryMath.napLine(.init(id: UUID(), startedAt: now, minutes: 10, snoozes: 3, upAt: nil, tries: 0))
        #expect(three.contains("snoozed 3 times"))
    }

    @Test func napsAreAnAttemptKindThatSurvivesStorage() {
        #expect(AttemptKind(rawValue: "nap") == .nap)
    }
}

struct NapStatusTests {
    @Test func theStatusPillTalksAboutTheNapWhileOneIsSet() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let status = HomeStatus.make(
            warnings: [], lastError: nil, authorizationNotDetermined: false, hasAlarms: true,
            hasEnabledAlarm: true, nextRing: now.addingTimeInterval(86_400), now: now,
            napText: "Napping until 3:42 PM"
        )
        #expect(status?.readyText == "Napping until 3:42 PM")
    }

    @Test func aNapGivesAPillEvenWithNoAlarms() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let none = HomeStatus.make(
            warnings: [], lastError: nil, authorizationNotDetermined: false, hasAlarms: false,
            hasEnabledAlarm: false, nextRing: nil, now: now
        )
        #expect(none == nil)
        let napping = HomeStatus.make(
            warnings: [], lastError: nil, authorizationNotDetermined: false, hasAlarms: false,
            hasEnabledAlarm: false, nextRing: nil, now: now, napText: "Napping until 3:42 PM"
        )
        #expect(napping?.readyText == "Napping until 3:42 PM")
        #expect(napping?.isReady == true)
    }
}
