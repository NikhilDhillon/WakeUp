import Foundation
import SwiftData

/// What kind of check an attempt was.
enum AttemptKind: String, Codable, Sendable {
    /// The morning's main check.
    case wake
    /// The "Still up?" check after a pass.
    case followUp
    /// A nap's check (and its "Still at your desk?" check). Never part of a
    /// morning: it doesn't touch the streak or the morning summaries.
    case nap
}

/// One photo check, kept so the History screen can show how mornings went.
/// The photo itself is not kept unless "Keep a small thumbnail" is on.
@Model
final class ProofAttempt {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = AttemptKind.wake.rawValue
    var missionName: String = ""
    var challenge: String = ""
    var methodRaw: String = CheckSource.decisions.rawValue
    var passed: Bool = false
    /// How long the check took, in seconds.
    var durationSeconds: Double = 0
    /// Input tokens OpenAI billed. 0 = unknown.
    var inputTokens: Int = 0
    /// The probability of each check, as JSON `{ "same_place": 0.93, … }`.
    var probabilitiesData: Data = Data()
    var weakestCheckRaw: String = ""
    var weakestConfidence: Double = 0
    @Attribute(.externalStorage) var thumbnail: Data?
    /// When the alarm this attempt answered was set to ring (its first
    /// ring). nil for attempts saved before this was kept.
    var alarmTime: Date?

    init(
        date: Date, kind: AttemptKind, missionName: String, challenge: String,
        verdict: Verdict, passed: Bool, duration: TimeInterval, thumbnail: Data?,
        alarmTime: Date? = nil
    ) {
        self.date = date
        self.alarmTime = alarmTime
        self.kindRaw = kind.rawValue
        self.missionName = missionName
        self.challenge = challenge
        self.methodRaw = verdict.method.rawValue
        self.passed = passed
        self.durationSeconds = duration
        self.inputTokens = verdict.inputTokens ?? 0
        self.probabilitiesData = (try? JSONEncoder().encode(
            Dictionary(uniqueKeysWithValues: verdict.probabilities.map { ($0.key.rawValue, $0.value) })
        )) ?? Data()
        self.weakestCheckRaw = verdict.weakestCheck?.rawValue ?? ""
        self.weakestConfidence = verdict.overallConfidence
        self.thumbnail = thumbnail
    }

    var kind: AttemptKind { AttemptKind(rawValue: kindRaw) ?? .wake }
    var method: CheckSource { CheckSource(rawValue: methodRaw) ?? .decisions }
    var weakestCheck: ProofCheck? { ProofCheck(rawValue: weakestCheckRaw) }

    /// Each check's confidence (screen check already inverted), in order.
    var confidences: [(check: ProofCheck, value: Double)] {
        let raw = (try? JSONDecoder().decode([String: Double].self, from: probabilitiesData)) ?? [:]
        return ProofCheck.allCases.compactMap { check in
            guard let p = raw[check.rawValue] else { return nil }
            return (check, check.wantsYes ? p : 1 - p)
        }
    }

    var info: AttemptInfo { AttemptInfo(date: date, kind: kind, passed: passed, alarmTime: alarmTime) }
}
