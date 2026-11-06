import ActivityKit
import AlarmKit
import Foundation
import Observation
import SwiftUI

/// Wraps AlarmKit. AlarmKit always shows a Stop button we can't remove, so a
/// wake-up is a *chain* of alarms a few minutes apart (7:00, 7:03, 7:06 …)
/// that only a passing proof photo cancels.
///
/// Mornings are scheduled ahead as fixed-date chains for the next few days
/// (see `SchedulePlanner`), and topped up every time the app opens, after
/// every pass, and by a background refresh. So the alarm rings on its own
/// on the days the app isn't opened.
@MainActor
@Observable
final class AlarmService {
    static let shared = AlarmService()

    /// The developer test chain uses this alarm ID.
    static let testAlarmID = UUID(uuidString: "00000000-0000-0000-0000-00000000DE57")!

    private(set) var authorization: AlarmManager.AuthorizationState
    private(set) var alarms: [Alarm] = []
    private(set) var chains: [ScheduledChain] = []
    var lastError: String?

    private let manager = AlarmManager.shared
    private let store = ScheduleStore()
    private var isReconciling = false
    private var needsAnotherPass = false
    /// Slots being scheduled right now, so cleanup doesn't mistake them for strays.
    private var inFlight = Set<UUID>()

    private let learnedLimitKey = "alarmKit.learnedSlotLimit"

    private init() {
        authorization = manager.authorizationState
        alarms = (try? manager.alarms) ?? []
        chains = store.chains
        Task { await observeAlarms() }
        Task { await observeAuthorization() }
    }

    // MARK: - State

    func alarms(in chain: ScheduledChain) -> [Alarm] {
        let ids = Set(chain.slotIDs)
        return alarms.filter { ids.contains($0.id) }
    }

    /// Chains whose first alarm has rung and that haven't run out.
    func startedChains(now: Date = .now) -> [ScheduledChain] {
        chains.filter { $0.hasStarted(at: now) && !$0.isExpired(at: now) }
    }

    var isRinging: Bool {
        alarms.contains { $0.state == .alerting }
    }

    /// How many alarms iOS accepted before it said no, once it has said so.
    var learnedSlotLimit: Int? {
        let value = UserDefaults.standard.integer(forKey: learnedLimitKey)
        return value > 0 ? value : nil
    }

    // MARK: - Permission

    func requestAuthorization() async {
        do {
            authorization = try await manager.requestAuthorization()
        } catch {
            lastError = "Couldn't ask for alarm permission: \(error.localizedDescription)"
        }
    }

    private func ensureAuthorized(prompt: Bool) async -> Bool {
        if authorization == .notDetermined, prompt {
            await requestAuthorization()
        }
        if authorization != .authorized {
            if prompt { lastError = "Alarms aren't allowed. Turn them on in Settings > WakeUp." }
            return false
        }
        return true
    }

    // MARK: - Keeping the schedule up to date

    /// Saves the alarms (so the scheduler can read them without the
    /// database) and brings AlarmKit in line with them.
    func update(specs: [AlarmSpec]) async {
        store.specs = specs
        // Only ask for permission once there is an alarm that needs it.
        await reconcile(prompt: specs.contains { $0.isEnabled })
    }

    /// Makes AlarmKit match the saved alarms: adds mornings that are
    /// missing, cancels ones that no longer match, forgets old ones.
    /// `prompt` is false in the background, where a permission dialog
    /// can't appear.
    func reconcile(now: Date = .now, prompt: Bool = false) async {
        if isReconciling {
            needsAnotherPass = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsAnotherPass = false
            await reconcileOnce(now: now, prompt: prompt)
        } while needsAnotherPass
    }

    private func reconcileOnce(now: Date, prompt: Bool) async {
        refresh()
        guard await ensureAuthorized(prompt: prompt) else { return }

        let plan = SchedulePlanner.plan(
            specs: store.specs,
            existing: store.chains,
            now: now,
            slotBudget: learnedSlotLimit
        )
        for chain in plan.cancel + plan.expire {
            cancelSlots(of: chain)
            store.remove(chainID: chain.id)
        }
        cancelStrays()
        chains = store.chains

        for planned in plan.create {
            let result = await schedule(
                alarmID: planned.alarmID, kind: .main, day: planned.day, start: planned.start,
                count: planned.count, interval: planned.interval, signature: planned.signature,
                sound: planned.sound
            )
            if result.hitLimit { break }
        }
        chains = store.chains
        refresh()
    }

    /// Cancels AlarmKit alarms that belong to no chain (left over from an
    /// older version or an interrupted schedule).
    private func cancelStrays() {
        let known = Set(store.chains.flatMap(\.slotIDs)).union(inFlight)
        for alarm in (try? manager.alarms) ?? [] where !known.contains(alarm.id) {
            try? manager.stop(id: alarm.id)
            try? manager.cancel(id: alarm.id)
        }
    }

    // MARK: - Chains

    /// Schedules the "Still up?" chain after a pass.
    func scheduleFollowUp(for spec: AlarmSpec, delay: TimeInterval, now: Date = .now) async {
        guard await ensureAuthorized(prompt: false) else { return }
        let start = now.addingTimeInterval(max(delay, 60))
        _ = await schedule(
            alarmID: spec.id, kind: .followUp, day: Calendar.current.startOfDay(for: now), start: start,
            count: AlarmSpec.followUpChainLength, interval: max(spec.chainInterval, 120),
            signature: SchedulePlanner.signature(of: spec), sound: spec.sound
        )
        chains = store.chains
    }

    /// A short chain for trying the alarm. Replaces the previous test chain.
    func scheduleTestChain(startingAt start: Date, count: Int, interval: TimeInterval) async {
        for chain in store.chains where chain.kind == .test { cancel(chain) }
        guard await ensureAuthorized(prompt: true) else { return }
        _ = await schedule(
            alarmID: Self.testAlarmID, kind: .test, day: Calendar.current.startOfDay(for: start), start: start,
            count: count, interval: interval, signature: "test"
        )
        chains = store.chains
    }

    private func schedule(
        alarmID: UUID, kind: ScheduledChain.Kind, day: Date, start: Date,
        count: Int, interval: TimeInterval, signature: String, sound: String = AlarmSound.standard.rawValue
    ) async -> (chain: ScheduledChain?, hitLimit: Bool) {
        let chainID = UUID()
        var scheduled: [UUID] = []
        var hitLimit = false
        let planned = (0..<count).map { _ in UUID() }
        inFlight.formUnion(planned)
        defer { inFlight.subtract(planned) }

        do {
            for (index, id) in planned.enumerated() {
                let fireDate = start.addingTimeInterval(Double(index) * interval)
                let configuration = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>(
                    schedule: .fixed(fireDate),
                    attributes: Self.attributes(kind: kind, chainID: chainID, index: index, count: count),
                    secondaryIntent: ProveAwakeIntent(alarmID: id.uuidString),
                    sound: Self.alertSound(named: sound)
                )
                _ = try await manager.schedule(id: id, configuration: configuration)
                scheduled.append(id)
            }
            lastError = nil
        } catch AlarmManager.AlarmError.maximumLimitReached {
            hitLimit = true
            let total = ((try? manager.alarms) ?? []).count
            if total > 0 { UserDefaults.standard.set(total, forKey: learnedLimitKey) }
            lastError = "iOS only allows \(total) alarms at once, so the later mornings aren't scheduled yet. Use shorter chains or fewer alarms."
        } catch {
            lastError = "Couldn't schedule alarm \(scheduled.count + 1): \(error.localizedDescription)"
        }

        guard !scheduled.isEmpty else { return (nil, hitLimit) }
        let chain = ScheduledChain(
            id: chainID, alarmID: alarmID, kind: kind, day: day, start: start, interval: interval,
            slotIDs: scheduled, timeZoneID: Calendar.current.timeZone.identifier, signature: signature
        )
        store.add(chain)
        chains = store.chains
        return (chain, hitLimit)
    }

    private static func alertSound(named raw: String) -> ActivityKit.AlertConfiguration.AlertSound {
        guard let file = AlarmSound(rawValue: raw)?.fileName else { return .default }
        return .named(file)
    }

    /// Stops anything ringing in the chain and cancels every alarm left.
    func cancel(_ chain: ScheduledChain) {
        cancelSlots(of: chain)
        store.remove(chainID: chain.id)
        chains = store.chains
        refresh()
    }

    private func cancelSlots(of chain: ScheduledChain) {
        for id in chain.slotIDs {
            try? manager.stop(id: id)
            try? manager.cancel(id: id)
        }
    }

    /// Cancels every alarm this app has scheduled and forgets the chains.
    func cancelEverything() {
        for alarm in (try? manager.alarms) ?? alarms {
            try? manager.stop(id: alarm.id)
            try? manager.cancel(id: alarm.id)
        }
        store.clear()
        chains = []
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
        chains = store.chains
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

    private static func attributes(
        kind: ScheduledChain.Kind, chainID: UUID, index: Int, count: Int
    ) -> AlarmAttributes<WakeAlarmMetadata> {
        let title: LocalizedStringResource
        switch (kind, index) {
        case (.followUp, 0): title = "Still up? Prove it again"
        case (.followUp, _): title = "Still up? (\(index + 1) of \(count))"
        case (_, 0): title = "Time to prove you're up"
        default: title = "Still not up? (\(index + 1) of \(count))"
        }
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
