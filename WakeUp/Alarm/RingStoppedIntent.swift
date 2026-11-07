import AlarmKit
import AppIntents
import Foundation

/// Runs when Stop is pressed on any ring. AlarmKit always shows a Stop
/// button we can't remove, so:
///
/// - on an earlier ring, a notification says when the next ring comes;
/// - on the last ring, it comes straight back a few seconds later, again
///   and again, until a proof photo passes (which cancels the chain, so
///   there's nothing left to bring back).
struct RingStoppedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Ring stopped" }
    static var description: IntentDescription { "Says when the next ring comes, or rings the last one again." }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Chain ID")
    var chainID: String

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(chainID: String, alarmID: String) {
        self.chainID = chainID
        self.alarmID = alarmID
    }

    init() {
        self.chainID = ""
        self.alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        if let chain = UUID(uuidString: chainID), let alarm = UUID(uuidString: alarmID) {
            await AlarmService.shared.ringStopped(chainID: chain, alarmID: alarm)
        }
        return .result()
    }
}
