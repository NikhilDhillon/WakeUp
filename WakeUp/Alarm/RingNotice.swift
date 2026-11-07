import Foundation
import UserNotifications

/// The note that appears after you press Stop on a ring, saying when the
/// next one comes. Each new note replaces the last one.
enum RingNotice {
    private static let identifier = "wakeup.ring-stopped"

    /// Asks for permission to show notes, once, while the app is open.
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert])
    }

    /// The note's wording. `ring` and `total` are nil for the last ring,
    /// which rings again instead of moving on.
    static func text(next: Date, ring: Int?, total: Int?, now: Date = .now) -> (title: String, body: String) {
        let time = next.formatted(date: .omitted, time: .shortened)
        guard let ring, let total else {
            let seconds = max(Int(next.timeIntervalSince(now).rounded()), 1)
            let when = seconds < 60 ? "in \(seconds) seconds" : "at \(time)"
            return ("Ringing again \(when)", "That was the last ring. Only a proof photo stops it.")
        }
        return ("Next ring at \(time)", "Ring \(ring) of \(total). Only a proof photo stops them.")
    }

    /// The title on the ringing alarm, with the next ring's time when
    /// there is one: "Still not up? (2 of 10) · next 7:06 AM".
    static func alarmTitle(kind: ScheduledChain.Kind, index: Int, count: Int, next: Date?) -> String {
        let base: String
        switch (kind, index) {
        case (.followUp, 0): base = "Still up? Prove it again"
        case (.followUp, _): base = "Still up? (\(index + 1) of \(count))"
        case (_, count - 1): return "Last ring: only a photo stops it"
        case (_, 0): base = "Time to prove you're up"
        default: base = "Still not up? (\(index + 1) of \(count))"
        }
        guard let next else { return base }
        return "\(base) · next \(next.formatted(date: .omitted, time: .shortened))"
    }

    static func post(next: Date, ring: Int?, total: Int?) async {
        let words = text(next: next, ring: ring, total: total)
        let content = UNMutableNotificationContent()
        content.title = words.title
        content.body = words.body
        content.interruptionLevel = .active
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// Clears the note once it's no longer true (a proof passed).
    static func clear() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
