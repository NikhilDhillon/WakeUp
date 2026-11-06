import Foundation

/// Things that could stop tomorrow's alarm from working, worked out from
/// plain values so the rules can be tested.
struct HealthInputs: Equatable {
    var alarmsAllowed: Bool
    var hasEnabledAlarm: Bool
    var lowPowerMode: Bool
    /// 0–1, or a negative number when unknown.
    var batteryLevel: Float
    var isCharging: Bool
    /// Days since this build was installed, for builds that expire (free Apple ID). nil = doesn't expire.
    var daysSinceInstall: Int?
    var hasProof: Bool
    var canCheckPhoto: Bool
    var cameraDenied: Bool
}

enum HealthWarning: Equatable, Identifiable {
    case alarmsBlocked
    case cameraDenied
    case lowPowerMode
    case lowBattery
    case buildExpiring(daysLeft: Int)
    case noProof
    case cannotCheckPhoto

    var id: String {
        switch self {
        case .alarmsBlocked: "alarmsBlocked"
        case .cameraDenied: "cameraDenied"
        case .lowPowerMode: "lowPowerMode"
        case .lowBattery: "lowBattery"
        case .buildExpiring: "buildExpiring"
        case .noProof: "noProof"
        case .cannotCheckPhoto: "cannotCheckPhoto"
        }
    }

    var message: String {
        switch self {
        case .alarmsBlocked:
            "Alarms are blocked. Turn them on in Settings > WakeUp, or nothing will ring."
        case .cameraDenied:
            "The camera is blocked, so you can't take the proof photo. Turn it on in Settings > WakeUp."
        case .lowPowerMode:
            "Low Power Mode limits background refresh. Open WakeUp each evening so tomorrow's alarms are scheduled."
        case .lowBattery:
            "The battery is low. Charge your phone tonight so the alarm can ring."
        case .buildExpiring(let days):
            days <= 0
                ? "This build has expired or is about to. Reinstall it from Xcode, or alarms stop working."
                : "This build expires in \(days) day\(days == 1 ? "" : "s"). Reinstall it from Xcode before then."
        case .noProof:
            "No proof is set up, so the alarm can only be stopped without a photo."
        case .cannotCheckPhoto:
            "Photos can't be checked yet. Add your OpenAI key, a service URL, or switch to the on-phone check in Settings."
        }
    }
}

enum HealthCheck {
    /// Free Apple ID builds stop opening after this many days.
    static let freeBuildLifetimeDays = 7
    static let warnFromDay = 5
    static let lowBatteryLevel: Float = 0.2

    static func warnings(_ input: HealthInputs) -> [HealthWarning] {
        var result: [HealthWarning] = []
        if !input.alarmsAllowed { result.append(.alarmsBlocked) }
        if input.cameraDenied { result.append(.cameraDenied) }
        guard input.hasEnabledAlarm else { return result }
        if input.lowPowerMode { result.append(.lowPowerMode) }
        if input.batteryLevel >= 0, input.batteryLevel < lowBatteryLevel, !input.isCharging {
            result.append(.lowBattery)
        }
        if let days = input.daysSinceInstall, days >= warnFromDay {
            result.append(.buildExpiring(daysLeft: max(freeBuildLifetimeDays - days, 0)))
        }
        if !input.hasProof { result.append(.noProof) }
        if !input.canCheckPhoto { result.append(.cannotCheckPhoto) }
        return result
    }
}
