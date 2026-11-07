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
        if let chain { AlarmService.shared.cancel(chain) }

        let isTest = chain?.kind == .test
        let spec = chain.flatMap { scheduleStore.spec(for: $0.alarmID) }
        let wasFollowUp = state.phase == .followUpRinging
        let delay = state.proofPassed(
            at: now,
            followUpDelay: isTest ? 0 : (spec?.followUpDelay ?? 0),
            offline: offline && !isTest
        )
        // A quick test isn't a real morning.
        if !wasFollowUp, !isTest {
            lastPassed = now
            UserDefaults.standard.set(now, forKey: lastPassedKey)
        }
        stateStore.save(state)
        isShowingProof = false

        Task {
            if delay > 0, let spec {
                await AlarmService.shared.scheduleFollowUp(for: spec, delay: delay, now: now)
            }
            // Top up the next mornings now that today's chain is gone.
            await AlarmService.shared.reconcile()
        }
    }

    /// Used only when there's nothing to check against (no proof or no
    /// API key). Cancels the chain without recording a proof.
    func stopWithoutProof() {
        if let chain = activeChain { AlarmService.shared.cancel(chain) }
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
}
