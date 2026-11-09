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
    /// While a proof photo is being taken on the last ring, the extra ring
    /// waits until this time.
    private var repeatHoldUntil: Date?
    /// Rings silenced by "Prove I'm up" a moment ago. If stopping one also
    /// runs the Stop button's intent, that must not count as a snooze.
    private var silencedRings: [UUID: Date] = [:]

    /// Greater than 0 while a nap is being started, snoozed or handed to its
    /// follow-up, so cleanup doesn't mistake the gap between chains for a
    /// nap that ended.
    private var napBusyCount = 0

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
        let ids = Set(chain.allSlotIDs)
        return alarms.filter { ids.contains($0.id) }
    }

    /// Chains whose first alarm has rung and that haven't run out.
    func startedChains(now: Date = .now) -> [ScheduledChain] {
        chains.filter { $0.hasStarted(at: now) && !$0.isExpired(at: now) }
    }

    var isRinging: Bool {
        alarms.contains { $0.state == .alerting }
    }

    /// A nap is being started or snoozed right now: the chains are in flux.
    var isNapBusy: Bool { napBusyCount > 0 }

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
        let needsPermission = specs.contains { $0.isEnabled }
        await reconcile(prompt: needsPermission)
        // For the "Next ring at…" note after Stop. Asked after alarms, once.
        if needsPermission, authorization == .authorized {
            await RingNotice.requestPermissionIfNeeded()
        }
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
        // A morning chain that ran out was never passed (a pass cancels it
        // first), so that morning was missed. Logged for the streak.
        for chain in plan.expire where chain.kind == .main {
            store.recordMissed(day: chain.day)
        }
        for chain in plan.cancel + plan.expire {
            cancelSlots(of: chain)
            store.remove(chainID: chain.id)
        }
        cancelStrays()
        finishNapIfGone(now: now)
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
        let known = Set(store.chains.flatMap(\.allSlotIDs)).union(inFlight)
        for alarm in (try? manager.alarms) ?? [] where !known.contains(alarm.id) {
            try? manager.stop(id: alarm.id)
            try? manager.cancel(id: alarm.id)
        }
    }

    // MARK: - Chains

    /// Schedules the "Still up?" chain after a pass.
    func scheduleFollowUp(for spec: AlarmSpec, delay: TimeInterval, now: Date = .now) async {
        await scheduleFollowUp(
            alarmID: spec.id, delay: delay, interval: spec.chainInterval, sound: spec.sound,
            signature: SchedulePlanner.signature(of: spec), now: now
        )
    }

    /// Schedules the follow-up chain for any alarm or nap. `proofName` is
    /// set for naps, whose follow-up asks "Still at your desk?".
    func scheduleFollowUp(
        alarmID: UUID, delay: TimeInterval, interval: TimeInterval, sound: String, signature: String,
        proofName: String? = nil, now: Date = .now
    ) async {
        napBusyCount += 1
        defer { napBusyCount -= 1 }
        guard await ensureAuthorized(prompt: false) else { return }
        let start = now.addingTimeInterval(max(delay, 60))
        _ = await schedule(
            alarmID: alarmID, kind: .followUp, day: Calendar.current.startOfDay(for: now), start: start,
            count: AlarmSpec.followUpChainLength, interval: max(interval, 120),
            signature: signature, sound: sound, proofName: proofName
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
        count: Int, interval: TimeInterval, signature: String, sound: String = AlarmSound.standard.rawValue,
        proofName: String? = nil, noSnoozesLeft: Bool = false
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
                let next = index < count - 1 ? fireDate.addingTimeInterval(interval) : nil
                let configuration = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>(
                    schedule: .fixed(fireDate),
                    attributes: Self.attributes(
                        kind: kind, chainID: chainID, index: index, count: count, next: next,
                        proof: proofName, noSnoozesLeft: noSnoozesLeft
                    ),
                    // Stop says when the next ring comes, or brings the last one back.
                    stopIntent: RingStoppedIntent(chainID: chainID.uuidString, alarmID: id.uuidString),
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
        RingNotice.clear()
        chains = store.chains
        refresh()
    }

    private func cancelSlots(of chain: ScheduledChain) {
        for id in chain.allSlotIDs {
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
        WakeCoordinator.shared.napEnded()
    }

    /// Silences the alarm that's ringing right now without cancelling the
    /// rest of the chain (used while you take the proof photo). On the last
    /// ring there's nothing left to ring, so it comes back after the photo
    /// window unless a proof passes first.
    func silence(alarmID: UUID, now: Date = .now) {
        let lastRingChain = store.chains.first { $0.lastSlotID == alarmID || $0.repeatSlotID == alarmID }
        if let lastRingChain {
            // Set before stopping, in case stopping also runs the Stop
            // button's intent: that re-ring must wait for the photo too.
            repeatHoldUntil = now.addingTimeInterval(ScheduledChain.ringAgainAfterProof)
        }
        silencedRings[alarmID] = now.addingTimeInterval(10)
        try? manager.stop(id: alarmID)
        refresh()
        if let lastRingChain {
            Task { await ringAgain(chainID: lastRingChain.id, after: ScheduledChain.ringAgainAfterProof, now: now) }
        }
    }

    /// The sound and gap a chain's alarm uses: the saved nap's, or the
    /// saved alarm's. nil when neither exists any more.
    func ringSettings(for chain: ScheduledChain) -> RingSettings? {
        RingSettings.resolve(alarmID: chain.alarmID, nap: store.nap, spec: store.spec(for: chain.alarmID))
    }

    /// Stop was pressed on a ring: say when the next one comes, or, on the
    /// last ring, bring it back and say when. On a nap with snoozes left,
    /// Stop is the snooze button instead.
    func ringStopped(chainID: UUID, alarmID: UUID, now: Date = .now) async {
        guard let chain = store.chains.first(where: { $0.id == chainID }) else { return }
        let wasSilenced = silencedRings[alarmID].map { $0 > now } ?? false
        silencedRings = silencedRings.filter { $0.value > now }
        if chain.kind == .nap, !wasSilenced, let nap = store.nap, nap.id == chain.alarmID, nap.snoozesLeft > 0 {
            // A snooze that can't be scheduled puts the old rings back
            // itself, so there's nothing more to do either way.
            await snoozeNap(now: now, stopped: alarmID)
            return
        }
        if chain.isLastRing(alarmID) {
            await ringAgain(chainID: chainID, after: ScheduledChain.ringAgainAfterStop, now: now)
            if let again = store.chains.first(where: { $0.id == chainID })?.repeatRing {
                await RingNotice.post(next: again, ring: nil, total: nil)
            }
        } else if let next = chain.nextRing(afterStopping: alarmID) {
            await RingNotice.post(next: next.date, ring: next.ring, total: next.total)
        }
    }

    /// Schedules the last ring again, `delay` from now, replacing any extra
    /// ring already waiting. Does nothing once the chain is gone (a proof
    /// passed or it was cancelled), which is what finally ends it.
    func ringAgain(chainID: UUID, after delay: TimeInterval, now: Date = .now) async {
        guard let chain = store.chains.first(where: { $0.id == chainID }),
              await ensureAuthorized(prompt: false)
        else { return }

        let fireDate = ScheduledChain.repeatFireDate(now: now, delay: delay, holdUntil: repeatHoldUntil)
        let count = max(chain.slotIDs.count, 1)
        let sound = ringSettings(for: chain)?.sound ?? AlarmSound.standard.rawValue
        let proof = chain.belongsToNap ? store.nap?.proofName : nil
        let id = UUID()
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        let configuration = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>(
            schedule: .fixed(fireDate),
            attributes: Self.attributes(
                kind: chain.kind, chainID: chain.id, index: count - 1, count: count, next: nil, proof: proof
            ),
            stopIntent: RingStoppedIntent(chainID: chain.id.uuidString, alarmID: id.uuidString),
            secondaryIntent: ProveAwakeIntent(alarmID: id.uuidString),
            sound: Self.alertSound(named: sound)
        )
        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
        } catch {
            lastError = "Couldn't ring the last alarm again: \(error.localizedDescription)"
            return
        }

        // Re-read: a proof may have passed meanwhile (then drop the new
        // ring), or another re-ring may have landed (then replace it).
        guard var latest = store.chains.first(where: { $0.id == chainID }) else {
            try? manager.cancel(id: id)
            return
        }
        if let previous = latest.repeatSlotID {
            try? manager.stop(id: previous)
            try? manager.cancel(id: previous)
        }
        latest.repeatSlotID = id
        latest.repeatRing = fireDate
        store.add(latest)
        chains = store.chains
        refresh()
    }

    // MARK: - Naps

    enum NapStartResult: Equatable {
        case started
        /// iOS accepted only `fit` of the nap's rings. A nap with that many rings would work.
        case tooManyAlarms(fit: Int)
        case failed(String)
    }

    /// The nap that's set, if any.
    var nap: NapSession? { store.nap }

    /// Starts a nap: cancels any earlier one, saves it, and schedules its
    /// chain at `nap.ringsAt`. A nap must never fail to ring without saying so.
    func startNap(_ nap: NapSession) async -> NapStartResult {
        guard await ensureAuthorized(prompt: true) else {
            return .failed(lastError ?? "Alarms aren't allowed. Turn them on in Settings > WakeUp.")
        }
        napBusyCount += 1
        defer { napBusyCount -= 1 }

        let earlier = store.nap
        for chain in store.chains where chain.kind == .nap || (earlier != nil && chain.alarmID == earlier?.id) {
            cancelSlots(of: chain)
            store.remove(chainID: chain.id)
        }
        store.nap = nap
        let result = await schedule(
            alarmID: nap.id, kind: .nap, day: Calendar.current.startOfDay(for: nap.ringsAt), start: nap.ringsAt,
            count: nap.chainLength, interval: nap.chainInterval, signature: NapSession.signature,
            sound: nap.sound, proofName: nap.proofName
        )
        chains = store.chains

        if let chain = result.chain, chain.slotIDs.count == nap.chainLength {
            RingNotice.clear()
            refresh()
            return .started
        }
        // Some or none of the rings were accepted. A half-built nap would
        // ring and then go quiet, so none of it is kept.
        let fit = result.chain?.slotIDs.count ?? 0
        if let partial = result.chain {
            cancelSlots(of: partial)
            store.remove(chainID: partial.id)
        }
        store.nap = nil
        refresh()
        if result.hitLimit, fit > 0 { return .tooManyAlarms(fit: fit) }
        return .failed(lastError ?? "Couldn't start the nap.")
    }

    /// Cancels the nap and its chain. Refused once it has rung.
    @discardableResult
    func cancelNap(now: Date = .now) -> Bool {
        guard let nap = store.nap, nap.canCancel(at: now) else { return false }
        for chain in store.chains where chain.alarmID == nap.id { cancel(chain) }
        store.nap = nil
        refresh()
        WakeCoordinator.shared.napEnded()
        return true
    }

    /// Snoozes the nap: the whole chain starts again at now + the snooze
    /// length. The new count is saved before anything is scheduled, so a
    /// second Stop in a hurry finds the old chain gone and uses nothing.
    /// `stopped` is the ring whose Stop was pressed, if any.
    @discardableResult
    func snoozeNap(now: Date = .now, stopped: UUID? = nil) async -> Bool {
        guard let nap = store.nap,
              let updated = nap.snoozed(at: now),
              let old = store.chains.first(where: { $0.kind == .nap && $0.alarmID == nap.id }),
              authorization == .authorized
        else { return false }

        napBusyCount += 1
        defer { napBusyCount -= 1 }

        // Nothing below awaits until the new count is saved.
        cancelSlots(of: old)
        store.remove(chainID: old.id)
        store.nap = updated
        chains = store.chains

        let result = await schedule(
            alarmID: nap.id, kind: .nap, day: Calendar.current.startOfDay(for: updated.ringsAt),
            start: updated.ringsAt, count: updated.chainLength, interval: updated.chainInterval,
            signature: NapSession.signature, sound: updated.sound, proofName: updated.proofName,
            noSnoozesLeft: updated.usedAllSnoozes
        )

        if let chain = result.chain, chain.slotIDs.count == updated.chainLength {
            refresh()
            WakeCoordinator.shared.napSnoozed()
            await RingNotice.postSnoozed(until: updated.ringsAt, snoozesLeft: updated.snoozesLeft)
            return true
        }

        // iOS refused the new chain. A snooze can never end with nothing
        // ringing, so the old chain's remaining rings go back and the snooze
        // isn't counted.
        if let partial = result.chain {
            cancelSlots(of: partial)
            store.remove(chainID: partial.id)
        }
        var restored = nap
        restored.hasRung = true
        store.nap = restored
        await restoreRemainingRings(of: old, nap: restored, stopped: stopped, now: now)
        lastError = "Couldn't snooze: iOS refused the new alarms. The nap alarm will keep ringing."
        refresh()
        return false
    }

    /// Puts back the rings an old nap chain still had to ring. If the ring
    /// that was stopped was the last one, a single ring comes back.
    private func restoreRemainingRings(of old: ScheduledChain, nap: NapSession, stopped: UUID?, now: Date) async {
        let next = stopped.flatMap { old.nextRing(afterStopping: $0) }?.date
            ?? old.ringPosition(at: now).next
        var start = now.addingTimeInterval(ScheduledChain.ringAgainAfterStop)
        var count = 1
        var ringNumber: Int?
        if let next, old.interval > 0 {
            let index = Int((next.timeIntervalSince(old.start) / old.interval).rounded())
            start = next
            count = max(old.slotIDs.count - index, 1)
            ringNumber = index + 1
        }
        let result = await schedule(
            alarmID: nap.id, kind: .nap, day: old.day, start: start, count: count, interval: old.interval,
            signature: NapSession.signature, sound: nap.sound, proofName: nap.proofName
        )
        if let chain = result.chain {
            await RingNotice.post(next: chain.start, ring: ringNumber, total: ringNumber == nil ? nil : old.slotIDs.count)
        }
    }

    /// A proof passed for the nap. The record for History is written now.
    /// `keepForFollowUp` keeps the nap saved (so the follow-up chain can
    /// find its sound) until the follow-up chain is gone.
    func napPassed(at now: Date, keepForFollowUp: Bool) {
        guard var nap = store.nap else { return }
        if nap.passedAt == nil {
            store.addNapRecord(NapRecord(
                id: nap.id, startedAt: nap.startedAt, duration: nap.duration,
                snoozesUsed: nap.snoozesUsed, upAt: now
            ))
        }
        if keepForFollowUp {
            nap.passedAt = now
            store.nap = nap
        } else {
            store.nap = nil
        }
    }

    /// The follow-up passed, or the nap was stopped for good.
    func endNap() {
        store.nap = nil
    }

    /// Forgets a nap whose chains are all gone. If it rang out with no
    /// pass, History gets a record of it. Not for the mornings' streak.
    private func finishNapIfGone(now: Date) {
        guard !isNapBusy, let nap = store.nap,
              !store.chains.contains(where: { $0.alarmID == nap.id })
        else { return }
        if nap.passedAt == nil, nap.hasRung || nap.ringsAt <= now {
            store.addNapRecord(NapRecord(
                id: nap.id, startedAt: nap.startedAt, duration: nap.duration,
                snoozesUsed: nap.snoozesUsed, upAt: nil
            ))
        }
        store.nap = nil
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
        kind: ScheduledChain.Kind, chainID: UUID, index: Int, count: Int, next: Date?,
        proof: String? = nil, noSnoozesLeft: Bool = false
    ) -> AlarmAttributes<WakeAlarmMetadata> {
        let text = RingNotice.alarmTitle(
            kind: kind, index: index, count: count, next: next, proof: proof, noSnoozesLeft: noSnoozesLeft
        )
        let title: LocalizedStringResource = "\(text)"
        let proveButton = AlarmButton(
            text: "Prove I'm up",
            // Black reads on the cyan tint; white doesn't.
            textColor: .black,
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
            // The accent cyan, spelled out: iOS draws the alarm outside the
            // app, where the asset catalog's named colour isn't available.
            tintColor: Color(red: 0, green: 0.706, blue: 0.847)
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
