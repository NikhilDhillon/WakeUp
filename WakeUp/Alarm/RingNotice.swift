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
    /// `proof` and `noSnoozesLeft` only matter for naps.
    static func alarmTitle(
        kind: ScheduledChain.Kind, index: Int, count: Int, next: Date?,
        proof: String? = nil, noSnoozesLeft: Bool = false
    ) -> String {
        let base: String
        switch (kind, index) {
        case (.followUp, 0) where napPlace(proof) != nil: base = "Still at \(napPlace(proof)!)? Prove it again"
        case (.followUp, _) where napPlace(proof) != nil: base = "Still at \(napPlace(proof)!)? (\(index + 1) of \(count))"
        case (.followUp, 0): base = "Still up? Prove it again"
        case (.followUp, _): base = "Still up? (\(index + 1) of \(count))"
        case (.nap, 0) where noSnoozesLeft && count > 1: base = "No snoozes left: only a photo stops it"
        case (.nap, 0): base = napTitle(proof: proof)
        case (.nap, count - 1): return "Last ring: only a photo stops it"
        case (.nap, _): base = "Still napping? (\(index + 1) of \(count))"
        case (_, count - 1): return "Last ring: only a photo stops it"
        case (_, 0): base = "Time to prove you're up"
        default: base = "Still not up? (\(index + 1) of \(count))"
        }
        guard let next else { return base }
        return "\(base) · next \(next.formatted(date: .omitted, time: .shortened))"
    }

    /// "your desk" for a one-word proof named Desk; a longer name is used
    /// as it is. nil when there is no proof name (also for mornings).
    static func napPlace(_ proof: String?) -> String? {
        let name = proof?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return name.contains(" ") ? name : "your \(name.lowercased())"
    }

    /// "Nap's over: get to your desk".
    static func napTitle(proof: String?) -> String {
        guard let place = napPlace(proof) else { return "Nap's over: prove you're up" }
        return "Nap's over: get to \(place)"
    }

    /// The note after a snooze: "Snoozed until 3:52 PM · 1 snooze left".
    static func snoozeText(until time: Date, snoozesLeft: Int) -> (title: String, body: String) {
        let clock = time.formatted(date: .omitted, time: .shortened)
        let left: String
        switch snoozesLeft {
        case 0: left = "No snoozes left after this."
        case 1: left = "1 snooze left."
        default: left = "\(snoozesLeft) snoozes left."
        }
        return ("Snoozed until \(clock)", "\(left) Only a proof photo stops the nap alarm for good.")
    }

    static func postSnoozed(until time: Date, snoozesLeft: Int) async {
        let words = snoozeText(until: time, snoozesLeft: snoozesLeft)
        await post(title: words.title, body: words.body)
    }

    static func post(next: Date, ring: Int?, total: Int?) async {
        let words = text(next: next, ring: ring, total: total)
        await post(title: words.title, body: words.body)
    }

    private static func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
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
