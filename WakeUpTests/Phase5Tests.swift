import Foundation
import Testing
import UIKit
@testable import WakeUp

// MARK: Per-check thresholds and offline verdicts

struct ThresholdTests {
    private func verdict(_ overrides: [ProofCheck: Double] = [:]) -> Verdict {
        var probabilities: [ProofCheck: Double] = [
            .samePlace: 0.95, .personPresent: 0.97, .matchesDescription: 0.9,
            .challengeCompleted: 0.9, .appearsAwake: 0.92, .screenOrPrint: 0.02,
        ]
        probabilities.merge(overrides) { $1 }
        return Verdict(probabilities: probabilities, reason: nil)
    }

    @Test func placeIsHeldToAHigherBar() {
        let thresholds = Strictness.normal.thresholds
        #expect(thresholds.threshold(for: .samePlace) == 0.75)
        // 72% sure it's the right place passes a flat 70% bar but not the real one.
        let v = verdict([.samePlace: 0.72])
        #expect(v.passes(threshold: 0.7))
        #expect(!v.passes(using: thresholds))
        #expect(v.problems(using: thresholds) == [ProofCheck.samePlace.problem])
    }

    @Test func dimFaceIsJudgedMoreKindly() {
        let v = verdict([.appearsAwake: 0.62])
        #expect(!v.passes(threshold: 0.7))
        #expect(v.passes(using: Strictness.normal.thresholds)) // bar is 60%
    }

    @Test func barsStayBetweenZeroAndOne() {
        let lenient = Strictness.lenient.thresholds
        let strict = Strictness.strict.thresholds
        for check in ProofCheck.allCases {
            #expect((0...1).contains(lenient.threshold(for: check)))
            #expect((0...1).contains(strict.threshold(for: check)))
        }
        // An offset can't lift a bar past 97% (or past the base, if that's higher)...
        #expect(ProofThresholds(base: 0.98, offsets: [.samePlace: 0.1]).threshold(for: .samePlace) == 0.98)
        #expect(ProofThresholds(base: 0.90, offsets: [.samePlace: 0.1]).threshold(for: .samePlace) == 0.97)
        // ...and nothing goes above 1.
        #expect(ProofThresholds(base: 1.2, offsets: [:]).threshold(for: .personPresent) == 1)
    }

    @Test func offlineVerdictOnlyCountsWhatItJudged() {
        var v = Verdict(
            probabilities: [.personPresent: 0.95, .samePlace: 0.9],
            reason: nil, method: .offline, evaluated: OfflineVerifier.checks
        )
        #expect(v.passes(using: Strictness.normal.thresholds))
        #expect(v.overallConfidence == 0.9)
        v.probabilities[.personPresent] = 0.02
        #expect(v.problems(using: Strictness.lenient.thresholds) == [ProofCheck.personPresent.problem])
        #expect(v.weakestCheck == .personPresent)
    }
}

// MARK: Fallback

private final class Script: WakeVerifier, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Verdict, VerifierError>]
    private(set) var calls = 0

    init(_ results: [Result<Verdict, VerifierError>]) { self.results = results }

    func verify(_ request: VerificationRequest) async throws -> Verdict {
        let next: Result<Verdict, VerifierError> = lock.withLock {
            calls += 1
            return results.isEmpty ? .failure(.unreadableResponse) : results.removeFirst()
        }
        return try next.get()
    }
}

struct FallbackVerifierTests {
    private let request = VerificationRequest(
        photo: Data(), referencePhotos: [Data()], description: "d", challenge: "c", capturedAt: .now
    )
    private let online = Verdict(probabilities: ProofCheck.allCases.reduce(into: [:]) { $0[$1] = 0.9 }, reason: nil)
    private let offline = Verdict(
        probabilities: [.personPresent: 0.95, .samePlace: 0.9], reason: nil,
        method: .offline, evaluated: OfflineVerifier.checks
    )

    private func verifier(_ primary: Script, _ fallback: Script, retries: Int = 1) -> FallbackVerifier {
        FallbackVerifier(primary: primary, fallback: fallback, retries: retries, retryDelay: .zero)
    }

    @Test func goodAnswerNeverTouchesTheBackup() async throws {
        let primary = Script([.success(online)]), backup = Script([.success(offline)])
        let result = try await verifier(primary, backup).verify(request)
        #expect(result.method == .decisions)
        #expect(primary.calls == 1 && backup.calls == 0)
    }

    @Test func oneNetworkHiccupIsRetried() async throws {
        let primary = Script([.failure(.network("offline")), .success(online)]), backup = Script([])
        let result = try await verifier(primary, backup).verify(request)
        #expect(result.method == .decisions)
        #expect(primary.calls == 2 && backup.calls == 0)
    }

    @Test func twoNetworkFailuresFallBackToThePhone() async throws {
        let primary = Script([.failure(.network("a")), .failure(.network("b"))]), backup = Script([.success(offline)])
        let result = try await verifier(primary, backup).verify(request)
        #expect(result.method == .offline)
        #expect(primary.calls == 2 && backup.calls == 1)
    }

    @Test func creditsGoneOrBadKeyFallBackWithoutRetrying() async throws {
        for error in [VerifierError.rateLimited("no credits"), .invalidAPIKey] {
            let primary = Script([.failure(error)]), backup = Script([.success(offline)])
            let result = try await verifier(primary, backup).verify(request)
            #expect(result.method == .offline)
            #expect(primary.calls == 1)
        }
    }

    @Test func aRefusalOrBadRequestDoesNotFallBack() async {
        for error in [VerifierError.refused("no"), .badRequest("bad")] {
            let primary = Script([.failure(error)]), backup = Script([.success(offline)])
            await #expect(throws: error) { try await verifier(primary, backup).verify(request) }
            #expect(backup.calls == 0)
        }
    }

    @Test func backupFailingReportsTheOriginalProblem() async {
        let primary = Script([.failure(.server(503)), .failure(.server(503))])
        let backup = Script([.failure(.offlineCheckFailed("x"))])
        await #expect(throws: VerifierError.server(503)) { try await verifier(primary, backup).verify(request) }
    }
}

// MARK: Offline check

struct OfflineVerifierTests {
    private func image(_ draw: (CGContext, CGSize) -> Void) -> Data {
        let size = CGSize(width: 300, height: 300)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.9) { ctx in
            draw(ctx.cgContext, size)
        }
    }

    private var stripes: Data {
        image { ctx, size in
            for i in 0..<10 {
                ctx.setFillColor(i.isMultiple(of: 2) ? UIColor.red.cgColor : UIColor.blue.cgColor)
                ctx.fill(CGRect(x: CGFloat(i) * 30, y: 0, width: 30, height: size.height))
            }
        }
    }

    private var circles: Data {
        image { ctx, size in
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setFillColor(UIColor.green.cgColor)
            ctx.fillEllipse(in: CGRect(x: 40, y: 60, width: 120, height: 120))
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fillEllipse(in: CGRect(x: 170, y: 150, width: 90, height: 90))
        }
    }

    @Test func similarityMapsDistanceToAProbability() {
        #expect(OfflineVerifier.similarity(distance: 0) == 1)
        #expect(OfflineVerifier.similarity(distance: OfflineVerifier.sameDistance) == 1)
        #expect(OfflineVerifier.similarity(distance: OfflineVerifier.differentDistance) == 0)
        #expect(OfflineVerifier.similarity(distance: 5) == 0)
        let middle = (OfflineVerifier.sameDistance + OfflineVerifier.differentDistance) / 2
        #expect(abs(OfflineVerifier.similarity(distance: middle) - 0.5) < 0.001)
    }

    @Test func samePhotoIsTheClosestMatch() throws {
        let same = try OfflineVerifier.closestDistance(of: stripes, to: [stripes])
        let other = try OfflineVerifier.closestDistance(of: stripes, to: [circles])
        #expect(same < 0.05)
        // The simulator's Vision feature prints don't tell different images
        // apart (it reports 0.0 for stripes vs circles), so this only runs on a phone.
        #if !targetEnvironment(simulator)
        #expect(other > same, "same=\(same) other=\(other)")
        #endif
    }

    @Test func closestReferenceWins() throws {
        let both = try OfflineVerifier.closestDistance(of: stripes, to: [circles, stripes])
        #expect(both < 0.05)
    }

    @Test func noFaceMeansNoPass() throws {
        let request = VerificationRequest(
            photo: stripes, referencePhotos: [stripes], description: "d", challenge: "c", capturedAt: .now
        )
        let verdict = try OfflineVerifier.analyze(request)
        #expect(verdict.method == .offline)
        #expect(verdict.evaluated == OfflineVerifier.checks)
        #expect(verdict.confidence(.samePlace) > 0.95)
        #expect(verdict.confidence(.personPresent) < 0.1)
        #expect(!verdict.passes(using: Strictness.lenient.thresholds))
    }

    @Test func needsAtLeastOneReferencePhoto() {
        let request = VerificationRequest(
            photo: stripes, referencePhotos: [], description: "d", challenge: "c", capturedAt: .now
        )
        #expect(throws: VerifierError.self) { try OfflineVerifier.analyze(request) }
    }
}

// MARK: History

struct HistoryMathTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ d: Int, _ h: Int = 7, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    @Test func morningCountsTriesUpToTheFirstPass() {
        let attempts = [
            AttemptInfo(date: date(5, 7, 0), kind: .wake, passed: false),
            AttemptInfo(date: date(5, 7, 3), kind: .wake, passed: false),
            AttemptInfo(date: date(5, 7, 6), kind: .wake, passed: true),
            AttemptInfo(date: date(5, 7, 20), kind: .followUp, passed: false),
            AttemptInfo(date: date(5, 7, 22), kind: .followUp, passed: true),
        ]
        let summaries = HistoryMath.summaries(of: attempts, calendar: calendar)
        #expect(summaries.count == 1)
        #expect(summaries[0].tries == 3)
        #expect(summaries[0].upAt == date(5, 7, 6))
        #expect(summaries[0].followUpTries == 2)
        #expect(summaries[0].followUpPassed)
    }

    @Test func aMorningKeepsTheAlarmTimeItAnswered() {
        let summary = HistoryMath.summaries(of: [
            AttemptInfo(date: date(5, 6, 50), kind: .wake, passed: false, alarmTime: date(5, 6, 45)),
            AttemptInfo(date: date(5, 6, 53), kind: .wake, passed: true, alarmTime: date(5, 6, 45)),
            AttemptInfo(date: date(5, 7, 10), kind: .followUp, passed: true, alarmTime: date(5, 7, 5)),
        ], calendar: calendar)[0]
        // The follow-up's own chain doesn't replace the morning alarm.
        #expect(summary.alarmAt == date(5, 6, 45))
        #expect(summary.upAt == date(5, 6, 53))
    }

    @Test func olderAttemptsHaveNoAlarmTime() {
        let summary = HistoryMath.summaries(of: [AttemptInfo(date: date(5), kind: .wake, passed: true)], calendar: calendar)[0]
        #expect(summary.alarmAt == nil)
    }

    @Test func olderAttemptsGuessTheAlarmFromTheirWeekday() {
        // Nov 5, 2026 is a Thursday (weekday 5).
        let weekday = HistoryMath.AlarmTimeOfDay(hour: 6, minute: 45, weekdays: [2, 3, 4, 5, 6])
        let early = HistoryMath.AlarmTimeOfDay(hour: 5, minute: 30, weekdays: [2, 4, 6])
        let weekend = HistoryMath.AlarmTimeOfDay(hour: 9, minute: 30, weekdays: [1, 7])
        let alarms = [weekday, early, weekend]
        // The latest alarm before the photo wins.
        #expect(HistoryMath.likelyAlarm(before: date(5, 6, 50), alarms: alarms, calendar: calendar) == date(5, 6, 45))
        // An alarm after the photo didn't wake you.
        #expect(HistoryMath.likelyAlarm(before: date(5, 6, 40), alarms: [weekday], calendar: calendar) == nil)
        // Too long before the photo to count.
        #expect(HistoryMath.likelyAlarm(before: date(5, 10, 0), alarms: [weekday], calendar: calendar) == nil)
        // Not set for that weekday.
        #expect(HistoryMath.likelyAlarm(before: date(5, 9, 40), alarms: [weekend], calendar: calendar) == nil)
    }

    @Test func upAfterAlarmReadsNaturally() {
        let alarm = date(5, 6, 45)
        #expect(HistoryMath.upAfterAlarm(alarmAt: alarm, upAt: alarm.addingTimeInterval(30)) == "On time")
        #expect(HistoryMath.upAfterAlarm(alarmAt: alarm, upAt: date(5, 6, 50)) == "5 min after the alarm")
        #expect(HistoryMath.upAfterAlarm(alarmAt: alarm, upAt: date(5, 7, 45)) == "1 h after the alarm")
        #expect(HistoryMath.upAfterAlarm(alarmAt: alarm, upAt: date(5, 8, 5)) == "1 h 20 min after the alarm")
        // A photo before the alarm (opening the app early) is just on time.
        #expect(HistoryMath.upAfterAlarm(alarmAt: alarm, upAt: date(5, 6, 30)) == "On time")
    }

    @Test func aMorningWithNoPassHasNoTimeUp() {
        let summary = HistoryMath.summaries(of: [AttemptInfo(date: date(5), kind: .wake, passed: false)], calendar: calendar)[0]
        #expect(summary.upAt == nil)
        #expect(summary.tries == 1)
    }

    @Test func newestMorningIsFirst() {
        let summaries = HistoryMath.summaries(of: [
            AttemptInfo(date: date(3), kind: .wake, passed: true),
            AttemptInfo(date: date(5), kind: .wake, passed: true),
            AttemptInfo(date: date(4), kind: .wake, passed: true),
        ], calendar: calendar)
        #expect(summaries.map(\.day) == [date(5, 0), date(4, 0), date(3, 0)])
    }

    private func streak(passes: [Int], missed: [Int] = [], today: Int = 5, hour: Int = 20) -> Int {
        HistoryMath.streak(
            passDays: Set(passes.map { date($0) }),
            missedDays: Set(missed.map { date($0, 0) }),
            now: date(today, hour),
            calendar: calendar
        )
    }

    // 2026-11-05 is a Thursday.

    @Test func consecutiveMorningsBuildAStreak() {
        #expect(streak(passes: [3, 4, 5]) == 3)
    }

    @Test func aMorningThatRangOutBreaksIt() {
        #expect(streak(passes: [2, 3, 5], missed: [4]) == 1)
    }

    @Test func todayStillOpenDoesNotBreakIt() {
        #expect(streak(passes: [3, 4], today: 5) == 2)
    }

    @Test func daysWithNoAlarmRingingDontBreakIt() {
        // No pass and nothing missed on the 4th (no alarm, a skip, or an
        // alarm turned off): it neither counts nor breaks the streak.
        #expect(streak(passes: [2, 3, 5]) == 3)
    }

    @Test func turningAlarmsOffLaterChangesNothing() {
        // The streak only reads what happened, so the same passes and misses
        // give the same answer whatever alarms are on now.
        let before = streak(passes: [1, 2, 3, 4, 5])
        #expect(before == 5)
        #expect(streak(passes: [1, 2, 3, 4, 5]) == before)
    }

    @Test func aPassWinsOverAMissTheSameDay() {
        // Up with the 6:45 alarm, then a later alarm that day went unanswered.
        #expect(streak(passes: [4, 5], missed: [5]) == 2)
    }

    @Test func noPassesIsZero() {
        #expect(streak(passes: []) == 0)
        #expect(streak(passes: [], missed: [4]) == 0)
    }
}
