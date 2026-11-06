import AlarmKit
import Foundation
import Observation
import SwiftUI

/// Wraps AlarmKit. AlarmKit always shows a Stop button we can't remove, so
/// instead of one alarm we schedule a *chain* (e.g. 7:00, 7:03, 7:06 ...)
/// and only cancel the rest of it once the proof photo passes.
@MainActor
@Observable
final class AlarmService {
    static let shared = AlarmService()

    private(set) var authorization: AlarmManager.AuthorizationState
    private(set) var alarms: [Alarm] = []
    var lastError: String?

    private let manager = AlarmManager.shared
    private let chainStore = ChainStore()

    private init() {
        authorization = manager.authorizationState
        alarms = (try? manager.alarms) ?? []
        Task { await observeAlarms() }
        Task { await observeAuthorization() }
    }

    // MARK: - State

    /// IDs of the alarms in the current chain that AlarmKit still knows about.
    var chainAlarms: [Alarm] {
        let ids = Set(chainStore.ids)
        return alarms.filter { ids.contains($0.id) }
    }

    /// True once the first alarm of the chain has gone off and the chain
    /// hasn't been cleared by a passing proof yet.
    var chainHasStarted: Bool {
        guard let start = chainStore.start else { return false }
        return start <= .now && !chainStore.ids.isEmpty
    }

    var isRinging: Bool {
        chainAlarms.contains { $0.state == .alerting }
    }

    // MARK: - Permission

    func requestAuthorization() async {
        do {
            authorization = try await manager.requestAuthorization()
        } catch {
            lastError = "Couldn't ask for alarm permission: \(error.localizedDescription)"
        }
    }

    // MARK: - Scheduling

    /// Schedules `count` alarms, `interval` seconds apart, starting at `start`.
    /// Replaces any chain that was already scheduled.
    func scheduleChain(startingAt start: Date, count: Int, interval: TimeInterval) async {
        cancelChain()
        if authorization != .authorized {
            await requestAuthorization()
            guard authorization == .authorized else {
                lastError = "Alarms aren't allowed. Turn them on in Settings > WakeUp."
                return
            }
        }

        let chainID = UUID()
        var scheduled: [UUID] = []
        do {
            for index in 0..<count {
                let id = UUID()
                let fireDate = start.addingTimeInterval(Double(index) * interval)
                let configuration = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>(
                    schedule: .fixed(fireDate),
                    attributes: Self.attributes(chainID: chainID, index: index, count: count),
                    secondaryIntent: ProveAwakeIntent(alarmID: id.uuidString),
                    sound: .default
                )
                _ = try await manager.schedule(id: id, configuration: configuration)
                scheduled.append(id)
            }
            chainStore.save(ids: scheduled, start: start)
            lastError = nil
        } catch AlarmManager.AlarmError.maximumLimitReached {
            chainStore.save(ids: scheduled, start: start)
            lastError = "iOS only allowed \(scheduled.count) of \(count) alarms."
        } catch {
            chainStore.save(ids: scheduled, start: start)
            lastError = "Couldn't schedule alarm \(scheduled.count + 1): \(error.localizedDescription)"
        }
        refresh()
    }

    /// Stops anything ringing and cancels every remaining alarm in the chain.
    func cancelChain() {
        for id in chainStore.ids {
            try? manager.stop(id: id)
            try? manager.cancel(id: id)
        }
        chainStore.clear()
        refresh()
    }

    /// Cancels every alarm this app has scheduled, chain or not.
    func cancelEverything() {
        for alarm in alarms {
            try? manager.stop(id: alarm.id)
            try? manager.cancel(id: alarm.id)
        }
        chainStore.clear()
        refresh()
    }

    /// Silences the alarm that's ringing right now without cancelling the
    /// rest of the chain (used while you take the proof photo).
    func silence(alarmID: UUID) {
        try? manager.stop(id: alarmID)
        refresh()
    }

    func refresh() {
        alarms = (try? manager.alarms) ?? alarms
        authorization = manager.authorizationState
    }

    // MARK: - Helpers

    /// The next time the clock shows `time` (today if still ahead, else tomorrow).
    static func nextOccurrence(of time: Date, after now: Date = .now) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.nextDate(
            after: now,
            matching: DateComponents(hour: parts.hour, minute: parts.minute, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(86_400)
    }

    static func fireDate(of alarm: Alarm) -> Date? {
        if case .fixed(let date) = alarm.schedule { return date }
        return nil
    }

    private static func attributes(chainID: UUID, index: Int, count: Int) -> AlarmAttributes<WakeAlarmMetadata> {
        let title: LocalizedStringResource = index == 0
            ? "Time to prove you're up"
            : "Still not up? (\(index + 1) of \(count))"
        let proveButton = AlarmButton(
            text: "Prove I'm up",
            textColor: .white,
            systemImageName: "camera.fill"
        )
        let alert = AlarmPresentation.Alert(
            title: title,
            secondaryButton: proveButton,
            secondaryButtonBehavior: .custom
        )
        return AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeAlarmMetadata(chainID: chainID, index: index),
            tintColor: .orange
        )
    }

    // MARK: - Observation

    private func observeAlarms() async {
        for await updated in manager.alarmUpdates {
            alarms = updated
        }
    }

    private func observeAuthorization() async {
        for await state in manager.authorizationUpdates {
            authorization = state
        }
    }
}
