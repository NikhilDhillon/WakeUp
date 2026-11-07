import Foundation
import Testing
@testable import WakeUp

/// The last ring keeps coming back until a proof passes.
struct KeepRingingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func chain(slots: Int = 3, startedAgo: TimeInterval = 600) -> ScheduledChain {
        ScheduledChain(
            id: UUID(), alarmID: UUID(), kind: .main, day: now.addingTimeInterval(-3600),
            start: now.addingTimeInterval(-startedAgo), interval: 180,
            slotIDs: (0..<slots).map { _ in UUID() }, timeZoneID: "UTC", signature: "x"
        )
    }

    @Test func theExtraRingBelongsToTheChain() {
        var chain = chain()
        #expect(chain.allSlotIDs == chain.slotIDs)
        let extra = UUID()
        chain.repeatSlotID = extra
        #expect(chain.allSlotIDs == chain.slotIDs + [extra])
        #expect(chain.lastSlotID == chain.slotIDs.last)
    }

    @Test func theExtraRingKeepsTheChainFromExpiring() {
        // Started 3 hours ago: the planned last ring was long enough ago to expire...
        var chain = chain(startedAgo: 3 * 3600)
        #expect(chain.isExpired(at: now))
        // ...but a ring that's still coming back keeps it alive.
        chain.repeatRing = now.addingTimeInterval(5)
        #expect(!chain.isExpired(at: now))
        #expect(chain.lastRing == now.addingTimeInterval(5))
    }

    @Test func anEarlierExtraRingDoesNotShortenTheChain() {
        var chain = chain(startedAgo: 0)
        let planned = chain.lastRing
        chain.repeatRing = chain.start
        #expect(chain.lastRing == planned)
    }

    @Test func stopRingsAgainAlmostAtOnce() {
        let fire = ScheduledChain.repeatFireDate(now: now, delay: ScheduledChain.ringAgainAfterStop, holdUntil: nil)
        #expect(fire == now.addingTimeInterval(5))
    }

    @Test func stopDuringAPhotoWaitsForThePhotoWindow() {
        let hold = now.addingTimeInterval(ScheduledChain.ringAgainAfterProof)
        let fire = ScheduledChain.repeatFireDate(now: now, delay: ScheduledChain.ringAgainAfterStop, holdUntil: hold)
        #expect(fire == hold)
    }

    @Test func anOldPhotoWindowDoesNotDelayTheNextRing() {
        let fire = ScheduledChain.repeatFireDate(
            now: now, delay: ScheduledChain.ringAgainAfterStop, holdUntil: now.addingTimeInterval(-60)
        )
        #expect(fire == now.addingTimeInterval(5))
    }

    @Test func stoppingAnEarlierRingNamesTheNextOne() {
        let chain = chain(slots: 3)
        let next = chain.nextRing(afterStopping: chain.slotIDs[0])
        #expect(next?.date == chain.start.addingTimeInterval(180))
        #expect(next?.ring == 2)
        #expect(next?.total == 3)
        #expect(chain.nextRing(afterStopping: chain.slotIDs[1])?.ring == 3)
    }

    @Test func theLastRingHasNoNextOneItRingsAgain() {
        var chain = chain(slots: 3)
        let last = chain.slotIDs[2]
        #expect(chain.nextRing(afterStopping: last) == nil)
        #expect(chain.isLastRing(last))
        #expect(!chain.isLastRing(chain.slotIDs[0]))
        let extra = UUID()
        chain.repeatSlotID = extra
        #expect(chain.isLastRing(extra))
        #expect(chain.nextRing(afterStopping: UUID()) == nil)
    }

    @Test func theNoteSaysWhenAndWhichRing() {
        let next = now.addingTimeInterval(180)
        let time = next.formatted(date: .omitted, time: .shortened)
        let words = RingNotice.text(next: next, ring: 3, total: 10, now: now)
        #expect(words.title == "Next ring at \(time)")
        #expect(words.body == "Ring 3 of 10. Only a proof photo stops them.")

        let again = RingNotice.text(next: now.addingTimeInterval(5), ring: nil, total: nil, now: now)
        #expect(again.title == "Ringing again in 5 seconds")
    }

    @Test func ringingTitlesShowTheNextRing() {
        let next = now.addingTimeInterval(180)
        let time = next.formatted(date: .omitted, time: .shortened)
        #expect(RingNotice.alarmTitle(kind: .main, index: 0, count: 3, next: next) == "Time to prove you're up · next \(time)")
        #expect(RingNotice.alarmTitle(kind: .main, index: 1, count: 3, next: next) == "Still not up? (2 of 3) · next \(time)")
        #expect(RingNotice.alarmTitle(kind: .main, index: 2, count: 3, next: nil) == "Last ring: only a photo stops it")
        #expect(RingNotice.alarmTitle(kind: .main, index: 0, count: 1, next: nil) == "Last ring: only a photo stops it")
        #expect(RingNotice.alarmTitle(kind: .followUp, index: 1, count: 4, next: next) == "Still up? (2 of 4) · next \(time)")
    }

    @Test func chainsSavedBeforeThisStillLoad() throws {
        let saved = chain()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        json["repeatSlotID"] = nil
        json["repeatRing"] = nil
        let decoded = try JSONDecoder().decode(ScheduledChain.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.repeatSlotID == nil)
        #expect(decoded.allSlotIDs == saved.slotIDs)
    }
}

/// Mornings that rang out without a pass, kept for the streak.
struct MissedDaysTests {
    @Test func missedMorningsAreKeptByDay() throws {
        let suite = "MissedDaysTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ScheduleStore(defaults: defaults)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        store.recordMissed(day: now.addingTimeInterval(-3600), now: now, calendar: calendar)
        store.recordMissed(day: now.addingTimeInterval(-1800), now: now, calendar: calendar)
        #expect(store.missedDays == [calendar.startOfDay(for: now.addingTimeInterval(-3600))])

        // Very old ones are dropped as new ones come in.
        let ancient = calendar.date(byAdding: .day, value: -(ScheduleStore.missedDaysKept + 5), to: now)!
        defaults.set(try JSONEncoder().encode([ancient]), forKey: "history.missedDays")
        store.recordMissed(day: now, now: now, calendar: calendar)
        #expect(store.missedDays == [calendar.startOfDay(for: now)])

        store.clearMissedDays()
        #expect(store.missedDays.isEmpty)
    }
}
