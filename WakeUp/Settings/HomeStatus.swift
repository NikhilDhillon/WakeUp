import Foundation

/// What tapping the status pill's button does.
enum StatusAction: Equatable, Sendable {
    case retry
    case openSystemSettings
    case chooseProof
    case openAppSettings
    case showDetails
    case requestAuthorization

    var title: String {
        switch self {
        case .retry: "Retry"
        case .openSystemSettings: "Open Settings"
        case .chooseProof: "Choose"
        case .openAppSettings: "Set up"
        case .showDetails: "Details"
        case .requestAuthorization: "Allow"
        }
    }
}

/// One thing the status pill can report, worst first.
struct StatusProblem: Equatable, Identifiable, Sendable {
    var id: String
    /// Short, for the pill.
    var title: String
    /// The full message, for the details sheet.
    var detail: String
    var action: StatusAction?
}

/// What the pill under the "Alarms" title says.
struct HomeStatus: Equatable, Sendable {
    /// Every problem, most severe first. Empty = ready.
    var problems: [StatusProblem]
    /// "Ready for tomorrow", shown when there are no problems.
    var readyText: String

    var isReady: Bool { problems.isEmpty }
    var worst: StatusProblem? { problems.first }
    /// "+2" badge: how many problems are not the one shown.
    var extraCount: Int { max(problems.count - 1, 0) }

    /// Builds the pill from the health warnings and the alarm service's state.
    /// Returns nil when there are no alarms at all (the empty state covers that).
    static func make(
        warnings: [HealthWarning],
        lastError: String?,
        authorizationNotDetermined: Bool,
        hasAlarms: Bool,
        hasEnabledAlarm: Bool,
        nextRing: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> HomeStatus? {
        guard hasAlarms else { return nil }

        var problems: [StatusProblem] = []
        if let lastError {
            problems.append(StatusProblem(
                id: "lastError", title: "Couldn't schedule alarms", detail: lastError, action: .retry
            ))
        }
        for warning in warnings.sorted(by: { rank($0) < rank($1) }) {
            problems.append(problem(for: warning))
        }
        if authorizationNotDetermined {
            problems.append(StatusProblem(
                id: "authorization", title: "Allow alarms",
                detail: "WakeUp needs your permission to ring alarms.", action: .requestAuthorization
            ))
        }
        if !hasEnabledAlarm {
            problems.append(StatusProblem(
                id: "noAlarmOn", title: "No alarm is on",
                detail: "Every alarm is switched off, so nothing will ring.", action: nil
            ))
        }
        return HomeStatus(problems: problems, readyText: readyText(nextRing: nextRing, now: now, calendar: calendar))
    }

    /// "Ready for tomorrow", "Ready for today" or "Ready for Monday".
    static func readyText(nextRing: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let nextRing else { return "Ready" }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: nextRing)
        let gap = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch gap {
        case ...0: return "Ready for today"
        case 1: return "Ready for tomorrow"
        default:
            return "Ready for \(calendar.weekdaySymbols[calendar.component(.weekday, from: nextRing) - 1])"
        }
    }

    // MARK: Severity

    /// Lower = worse. Matches the order in the redesign plan.
    static func rank(_ warning: HealthWarning) -> Int {
        switch warning {
        case .alarmsBlocked: 0
        case .cameraDenied: 1
        case .noProof: 2
        case .cannotCheckPhoto: 3
        case .lowBattery: 4
        case .buildExpiring: 5
        case .lowPowerMode: 6
        }
    }

    static func problem(for warning: HealthWarning) -> StatusProblem {
        switch warning {
        case .alarmsBlocked:
            StatusProblem(id: warning.id, title: "Alarms are off for WakeUp", detail: warning.message, action: .openSystemSettings)
        case .cameraDenied:
            StatusProblem(id: warning.id, title: "Camera is blocked", detail: warning.message, action: .openSystemSettings)
        case .noProof:
            StatusProblem(id: warning.id, title: "Choose a place", detail: warning.message, action: .chooseProof)
        case .cannotCheckPhoto:
            StatusProblem(id: warning.id, title: "Photo check isn't set up", detail: warning.message, action: .openAppSettings)
        case .lowBattery:
            StatusProblem(id: warning.id, title: "Battery low, plug in tonight", detail: warning.message, action: nil)
        case .buildExpiring(let days):
            StatusProblem(
                id: warning.id,
                title: days <= 0 ? "Build has expired" : "Build expires in \(days) day\(days == 1 ? "" : "s")",
                detail: warning.message, action: nil
            )
        case .lowPowerMode:
            StatusProblem(id: warning.id, title: "Low Power Mode is on", detail: warning.message, action: .showDetails)
        }
    }
}

// MARK: Next Up card logic

/// The pure parts of the Next Up card: which alarm it shows, the countdown
/// text and the state of the Skip chip.
enum NextUp {
    /// Which alarm the card shows. The enabled alarm with the earliest real
    /// ring wins. With none on, the first alarm is shown greyed out.
    struct Pick: Equatable {
        var alarmID: UUID
        /// nil when the alarm is off (or never rings).
        var ring: Date?
        var isOff: Bool { ring == nil }
    }

    static func pick(specs: [AlarmSpec], now: Date, calendar: Calendar = .current) -> Pick? {
        let rings = specs.compactMap { spec -> (UUID, Date)? in
            SchedulePlanner.nextRing(of: spec, after: now, calendar: calendar).map { (spec.id, $0) }
        }
        if let best = rings.min(by: { $0.1 < $1.1 }) {
            return Pick(alarmID: best.0, ring: best.1)
        }
        // Nothing will ring: show the earliest time of day, greyed out.
        let first = specs.min { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        return first.map { Pick(alarmID: $0.id, ring: nil) }
    }

    /// "NEXT · IN 7 H 37 M", or "NEXT · MON" more than 24 hours away.
    static func countdownLabel(to ring: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = ring.timeIntervalSince(now)
        if seconds >= 24 * 3600 {
            let day = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: ring) - 1]
            return "NEXT · \(day.uppercased())"
        }
        let minutes = max(Int((seconds / 60).rounded(.up)), 1)
        let (h, m) = (minutes / 60, minutes % 60)
        switch (h, m) {
        case (0, _): return "NEXT · IN \(m) M"
        case (_, 0): return "NEXT · IN \(h) H"
        default: return "NEXT · IN \(h) H \(m) M"
        }
    }

    /// "in 7 hours 37 minutes", for VoiceOver.
    static func spokenCountdown(to ring: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = ring.timeIntervalSince(now)
        if seconds >= 24 * 3600 {
            return "on \(calendar.weekdaySymbols[calendar.component(.weekday, from: ring) - 1])"
        }
        let minutes = max(Int((seconds / 60).rounded(.up)), 1)
        let (h, m) = (minutes / 60, minutes % 60)
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        return "in " + parts.joined(separator: " ")
    }

    /// The Skip chip on the card.
    struct SkipChip: Equatable {
        var day: Date
        /// "Skip Friday" or "Undo skip".
        var title: String
        var isUndo: Bool
        /// Why the chip is greyed out; nil when it can be tapped.
        var disabledReason: String?
    }

    static func skipChip(for spec: AlarmSpec, now: Date, calendar: Calendar = .current) -> SkipChip? {
        guard spec.isEnabled,
              let occurrence = SchedulePlanner.skippableOccurrence(of: spec, after: now, calendar: calendar)
        else { return nil }
        if occurrence.isSkipped {
            return SkipChip(day: occurrence.day, title: "Undo skip", isUndo: true, disabledReason: nil)
        }
        let name = calendar.weekdaySymbols[calendar.component(.weekday, from: occurrence.day) - 1]
        return SkipChip(
            day: occurrence.day, title: "Skip \(name)", isUndo: false,
            disabledReason: SkipPolicy.unavailableReason(
                day: occurrence.day, skipped: spec.skippedDays, now: now, calendar: calendar
            )
        )
    }
}
