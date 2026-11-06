import Foundation
import Observation

/// Decides when the proof screen is shown and what happens when you pass.
@MainActor
@Observable
final class WakeCoordinator {
    static let shared = WakeCoordinator()

    var isShowingProof = false
    /// Stays the same for every retry of one morning, so a failed attempt
    /// doesn't reshuffle what you have to do.
    private(set) var challenge: Challenge = .random()
    private(set) var lastPassed: Date?

    private let lastPassedKey = "wake.lastPassed"

    private init() {
        lastPassed = UserDefaults.standard.object(forKey: lastPassedKey) as? Date
    }

    /// Called by the "Prove I'm up" alarm button.
    func proofRequested() {
        present()
    }

    /// If you open the app yourself while the chain is going, go straight
    /// to the proof screen.
    func appBecameActive() {
        if AlarmService.shared.chainHasStarted {
            present()
        }
    }

    func markPassed() {
        AlarmService.shared.cancelChain()
        lastPassed = .now
        UserDefaults.standard.set(lastPassed, forKey: lastPassedKey)
        isShowingProof = false
    }

    /// Closes the proof screen. The rest of the chain still rings.
    func notYet() {
        isShowingProof = false
    }

    private func present() {
        if !isShowingProof {
            challenge = .random()
        }
        isShowingProof = true
    }
}
