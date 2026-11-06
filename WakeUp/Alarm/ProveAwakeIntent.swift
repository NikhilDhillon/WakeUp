import AlarmKit
import AppIntents
import Foundation

/// Runs when you tap "Prove I'm up" on the ringing alarm. It silences the
/// alarm that's ringing (the rest of the chain stays scheduled) and brings
/// the app to the front.
struct ProveAwakeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Prove I'm up" }
    static var description: IntentDescription { "Opens WakeUp so you can take your proof photo." }
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        self.alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        let id = UUID(uuidString: alarmID)
        await MainActor.run {
            if let id {
                AlarmService.shared.silence(alarmID: id)
            }
            WakeCoordinator.shared.proofRequested()
        }
        return .result()
    }
}
