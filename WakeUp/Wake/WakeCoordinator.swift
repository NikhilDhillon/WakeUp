import Foundation
import Observation

/// Decides when the proof screen shows and what happens when you pass. The
/// morning's progress lives in a saved `WakeState`.
@MainActor
@Observable
final class WakeCoordinator {
    static let shared = WakeCoordinator()

    var isShowingProof = false
    private(set) var state: WakeState
    private(set) var lastPassed: Date?

    private let stateStore = WakeStateStore()
    private let scheduleStore = ScheduleStore()
    private let lastPassedKey = "wake.lastPassed"

    private init() {
        state = stateStore.load()
        lastPassed = UserDefaults.standard.object(forKey: lastPassedKey) as? Date
    }

    /// What you have to do in the photo. Fixed for the whole ring, so a
    /// failed attempt (or a restart) doesn't reshuffle it.
    var challenge: Challenge { state.challenge ?? .thumbsUp }

    /// True when this is the "Still up?" check after a pass.
    var isFollowUp: Bool { state.phase == .followUpRinging }

    /// True while the proof screen is for a nap, not a morning.
    var isNap: Bool { state.isNap }

    /// The saved nap, while this is a nap.
    var activeNap: NapSession? {
        guard state.isNap, let nap = scheduleStore.nap, nap.id == state.alarmID else { return nil }
        return nap
    }

    /// Which proof the screen asks for: the nap's, or the ringing alarm's.
    /// nil means the default proof.
    var activeProofID: String? {
        state.isNap ? activeNap?.missionID : activeSpec?.missionID
    }

    /// The Snooze button on the wake screen: a nap that has started ringing
    /// and still has snoozes. Not for the "Still at your desk?" check.
    func canSnooze(now: Date = .now) -> Bool {
        guard state.phase == .ringing, let nap = activeNap, nap.passedAt == nil, nap.snoozesLeft > 0,
              let chain = activeChain, chain.kind == .nap
        else { return false }
        return chain.hasStarted(at: now)
    }

    /// The alarm that is ringing, if it still exists.
    var activeSpec: AlarmSpec? {
        state.alarmID.flatMap { scheduleStore.spec(for: $0) }
    }

    /// The chain the proof screen is about: the follow-up chain during a
    /// follow-up, otherwise the earliest chain that has started.
    var activeChain: ScheduledChain? {
        let now = Date.now
        let started = scheduleStore.chains.filter { $0.hasStarted(at: now) && !$0.isExpired(at: now) }
        if state.phase == .followUpRinging,
           let followUp = started.filter({ $0.kind == .followUp }).min(by: { $0.start < $1.start }) {
            return followUp
        }
        return started.filter { $0.kind != .followUp }.min { $0.start < $1.start }
            ?? started.min { $0.start < $1.start }
            ?? waitingNapChain
    }

    /// The saved nap's chain before it has started (a nap that hasn't rung
    /// yet, or one that's snoozed). "I'm up early" cancels it.
    private var waitingNapChain: ScheduledChain? {
        guard let nap = scheduleStore.nap, nap.passedAt == nil else { return nil }
        return scheduleStore.chains.filter { $0.kind == .nap && $0.alarmID == nap.id }.min { $0.start < $1.start }
    }

    // MARK: Entry points

    /// Called by the "Prove I'm up" alarm button.
    func proofRequested() {
        sync()
        if state.isAwaitingProof { isShowingProof = true }
    }

    /// If you open the app yourself while a chain is going, go straight to
    /// the proof screen.
    func appBecameActive() {
        AlarmService.shared.refresh()
        sync()
        if state.isAwaitingProof { isShowingProof = true }
        Task { await AlarmService.shared.reconcile(prompt: false) }
    }

    /// Re-reads the scheduled chains and moves the morning along.
    func sync(now: Date = .now) {
        // A nap is between chains while it's being snoozed: not a time to judge it.
        guard !AlarmService.shared.isNapBusy else { return }
        scheduleStore.markNapRungIfStarted(now: now)
        let before = state
        state.sync(chains: scheduleStore.chains, now: now)
        if state != before { stateStore.save(state) }
    }

    // MARK: Results

    func proofFailed() {
        state.proofFailed()
        stateStore.save(state)
    }

    /// A proof passed. `offline` means the weaker on-phone check was used.
    func markPassed(offline: Bool = false) {
        let now = Date.now
        let chain = activeChain
        let nap = chain.flatMap { chain in scheduleStore.nap.flatMap { $0.id == chain.alarmID ? $0 : nil } }
        if let chain { AlarmService.shared.cancel(chain) }

        let isTest = chain?.kind == .test
        let spec = chain.flatMap { scheduleStore.spec(for: $0.alarmID) }
        let wasFollowUp = state.phase == .followUpRinging
        let delay = state.proofPassed(
            at: now,
            followUpDelay: isTest ? 0 : (nap?.followUpDelay ?? spec?.followUpDelay ?? 0),
            offline: offline && !isTest
        )
        // A quick test isn't a real morning, and a nap isn't a morning at all.
        if !wasFollowUp, !isTest, nap == nil {
            lastPassed = now
            UserDefaults.standard.set(now, forKey: lastPassedKey)
        }
        // The nap keeps its settings until its follow-up check is done.
        if nap != nil {
            if wasFollowUp {
                AlarmService.shared.endNap()
            } else {
                AlarmService.shared.napPassed(at: now, keepForFollowUp: delay > 0)
            }
        }
        stateStore.save(state)
        isShowingProof = false

        Task {
            if delay > 0, let nap {
                await AlarmService.shared.scheduleFollowUp(
                    alarmID: nap.id, delay: delay, interval: nap.chainInterval, sound: nap.sound,
                    signature: NapSession.signature, proofName: nap.proofName, now: now
                )
            } else if delay > 0, let spec {
                await AlarmService.shared.scheduleFollowUp(for: spec, delay: delay, now: now)
            }
            // Top up the next mornings now that today's chain is gone.
            await AlarmService.shared.reconcile()
        }
    }

    /// Used only when there's nothing to check against (no proof or no
    /// API key). Cancels the chain without recording a proof.
    func stopWithoutProof() {
        let chain = activeChain
        if let chain { AlarmService.shared.cancel(chain) }
        if let chain, scheduleStore.nap?.id == chain.alarmID {
            AlarmService.shared.napPassed(at: .now, keepForFollowUp: false)
        }
        state.stoppedWithoutProof()
        stateStore.save(state)
        isShowingProof = false
        Task { await AlarmService.shared.reconcile() }
    }

    /// Developer tool: forget where the morning was.
    func resetState() {
        state.reset()
        stateStore.save(state)
        isShowingProof = false
    }

    /// Closes the proof screen. The rest of the chain still rings.
    func notYet() {
        isShowingProof = false
    }

    // MARK: Naps

    /// "I'm up early": the proof screen opens now, before the nap rings or
    /// while it's snoozed. A pass cancels the chain that's waiting.
    func proveNapEarly() {
        guard let nap = scheduleStore.nap, nap.passedAt == nil else { return }
        sync()
        if !state.isAwaitingProof {
            state.beginNapEarly(alarmID: nap.id, day: Calendar.current.startOfDay(for: nap.ringsAt))
            stateStore.save(state)
        }
        isShowingProof = true
    }

    /// The wake screen's Snooze button.
    func snooze() async {
        let didSnooze = await AlarmService.shared.snoozeNap()
        if !didSnooze {
            // Nothing was snoozed (none left, or iOS refused): stay on the screen.
            return
        }
        napSnoozed()
    }

    /// A nap was snoozed (here or from the alarm's Stop button): the proof
    /// screen closes, and the state waits for the new chain.
    func napSnoozed() {
        isShowingProof = false
        let before = state
        if state.isNap, state.phase == .ringing {
            state.phase = .snoozed
        }
        if state != before { stateStore.save(state) }
    }

    /// The nap was cancelled: forget where it was.
    func napEnded() {
        guard state.isNap, state.phase == .ringing || state.phase == .snoozed else { return }
        state.reset()
        stateStore.save(state)
        isShowingProof = false
    }
}
