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
    /// Whole days until this build stops opening (free Apple ID builds), from
    /// its provisioning profile. nil = it doesn't expire, or it's unknown.
    var daysUntilBuildExpires: Int?
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
            "Photos can't be checked yet. Add your OpenAI key, a service URL, or switch to the on-phone check. Tap Set up."
        }
    }
}

enum HealthCheck {
    /// Warn once a build has this many days left or fewer (free Apple ID
    /// builds last 7 days).
    static let warnWhenDaysLeft = 2
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
        if let days = input.daysUntilBuildExpires, days <= warnWhenDaysLeft {
            result.append(.buildExpiring(daysLeft: max(days, 0)))
        }
        if !input.hasProof { result.append(.noProof) }
        if !input.canCheckPhoto { result.append(.cannotCheckPhoto) }
        return result
    }
}

/// When a development build stops opening. Free Apple ID builds carry a
/// provisioning profile (`embedded.mobileprovision`) whose ExpirationDate
/// is the real deadline; App Store and TestFlight builds have none.
enum BuildExpiry {
    /// The expiry date in a profile file: a signed wrapper around a plist.
    static func expirationDate(inProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        let object = try? PropertyListSerialization.propertyList(from: plist, format: nil)
        return (object as? [String: Any])?["ExpirationDate"] as? Date
    }

    /// Whole days left before `expiry` (0 on its last day or once passed).
    static func daysLeft(until expiry: Date, now: Date) -> Int {
        max(Int(expiry.timeIntervalSince(now) / 86_400), 0)
    }

    /// Days left for the running build, or nil when it doesn't expire.
    static func daysLeftForThisBuild(now: Date = .now) -> Int? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let expiry = expirationDate(inProfile: data)
        else { return nil }
        return daysLeft(until: expiry, now: now)
        #endif
    }
}
