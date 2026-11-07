import Foundation
import Testing
@testable import WakeUp

struct HealthCheckTests {
    private func healthy() -> HealthInputs {
        HealthInputs(
            alarmsAllowed: true, hasEnabledAlarm: true, lowPowerMode: false, batteryLevel: 0.8,
            isCharging: false, daysUntilBuildExpires: nil, hasProof: true, canCheckPhoto: true, cameraDenied: false
        )
    }

    @Test func healthyPhoneHasNoWarnings() {
        #expect(HealthCheck.warnings(healthy()).isEmpty)
    }

    @Test func blockedAlarmsAndCameraAlwaysWarn() {
        var input = healthy()
        input.alarmsAllowed = false
        input.cameraDenied = true
        input.hasEnabledAlarm = false
        #expect(HealthCheck.warnings(input) == [.alarmsBlocked, .cameraDenied])
    }

    @Test func lowPowerAndLowBatteryWarnOnlyWithAnAlarm() {
        var input = healthy()
        input.lowPowerMode = true
        input.batteryLevel = 0.1
        #expect(HealthCheck.warnings(input) == [.lowPowerMode, .lowBattery])
        input.isCharging = true
        #expect(HealthCheck.warnings(input) == [.lowPowerMode])
        input.hasEnabledAlarm = false
        #expect(HealthCheck.warnings(input).isEmpty)
    }

    @Test func unknownBatteryDoesNotWarn() {
        var input = healthy()
        input.batteryLevel = -1
        #expect(HealthCheck.warnings(input).isEmpty)
    }

    @Test func freeBuildWarnsInItsLastTwoDays() {
        var input = healthy()
        input.daysUntilBuildExpires = 6
        #expect(HealthCheck.warnings(input).isEmpty)
        input.daysUntilBuildExpires = 3
        #expect(HealthCheck.warnings(input).isEmpty)
        input.daysUntilBuildExpires = 2
        #expect(HealthCheck.warnings(input) == [.buildExpiring(daysLeft: 2)])
        input.daysUntilBuildExpires = 0
        #expect(HealthCheck.warnings(input) == [.buildExpiring(daysLeft: 0)])
    }

    @Test func expiryIsReadFromTheProvisioningProfile() {
        // A profile is binary signing data wrapped around a plist.
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CreationDate</key><date>2026-11-07T00:43:07Z</date>
        <key>ExpirationDate</key><date>2026-11-14T00:43:07Z</date>
        </dict></plist>
        """
        var data = Data([0x30, 0x82, 0x01, 0xFF, 0x00])
        data.append(Data(plist.utf8))
        data.append(Data([0xA0, 0x00, 0x31]))
        let expiry = BuildExpiry.expirationDate(inProfile: data)
        #expect(expiry == ISO8601DateFormatter().date(from: "2026-11-14T00:43:07Z"))

        // Installed minutes ago: a full 6 days and change left, so no warning.
        let justInstalled = ISO8601DateFormatter().date(from: "2026-11-07T01:24:00Z")!
        #expect(BuildExpiry.daysLeft(until: expiry!, now: justInstalled) == 6)
        let pastIt = ISO8601DateFormatter().date(from: "2026-11-15T00:00:00Z")!
        #expect(BuildExpiry.daysLeft(until: expiry!, now: pastIt) == 0)
    }

    @Test func noProfileMeansNoExpiry() {
        #expect(BuildExpiry.expirationDate(inProfile: Data("not a profile".utf8)) == nil)
    }

    @Test func missingProofOrCheckingWarns() {
        var input = healthy()
        input.hasProof = false
        input.canCheckPhoto = false
        #expect(HealthCheck.warnings(input) == [.noProof, .cannotCheckPhoto])
    }
}

struct AlarmSoundTests {
    private func spec(sound: String) -> AlarmSpec {
        AlarmSpec(
            id: UUID(), hour: 7, minute: 0, weekdays: .everyDay, missionID: nil, chainLength: 3,
            chainInterval: 180, followUpDelay: 0, isEnabled: true, skippedDays: [], sound: sound
        )
    }

    @Test func changingTheSoundReplansTheChains() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 20))!
        let alarm = spec(sound: AlarmSound.standard.rawValue)
        let planned = SchedulePlanner.plan(specs: [alarm], existing: [], now: now, calendar: cal).create
        let existing = planned.map {
            ScheduledChain(
                id: UUID(), alarmID: $0.alarmID, kind: .main, day: $0.day, start: $0.start, interval: $0.interval,
                slotIDs: [UUID()], timeZoneID: $0.timeZoneID, signature: $0.signature
            )
        }
        var loud = alarm
        loud.sound = AlarmSound.loud.rawValue
        let plan = SchedulePlanner.plan(specs: [loud], existing: existing, now: now, calendar: cal)
        #expect(plan.cancel.count == existing.count)
        #expect(plan.create.allSatisfy { $0.sound == AlarmSound.loud.rawValue })
    }

    @Test func alarmsSavedWithoutASoundStillLoad() throws {
        let json = """
        {"id":"\(UUID().uuidString)","hour":7,"minute":0,"weekdays":[2,3],"chainLength":3,
         "chainInterval":180,"followUpDelay":0,"isEnabled":true,"skippedDays":[]}
        """
        let spec = try JSONDecoder().decode(AlarmSpec.self, from: Data(json.utf8))
        #expect(spec.sound == AlarmSound.standard.rawValue)
        #expect(spec.weekdays == [2, 3])
    }

    @Test func loudSoundFileShipsInTheApp() {
        #expect(AlarmSound.standard.fileName == nil)
        let name = AlarmSound.loud.fileName
        #expect(name != nil)
        #expect(Bundle.main.url(forResource: "WakeAlarm", withExtension: "wav") != nil)
    }
}

struct ServiceSettingsTests {
    private func withURL(_ text: String?, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let old = defaults.string(forKey: AppSettings.serviceURLKey)
        defer { defaults.set(old, forKey: AppSettings.serviceURLKey) }
        defaults.set(text, forKey: AppSettings.serviceURLKey)
        body()
    }

    @Test func onlyHttpsAddressesAreAccepted() {
        withURL("https://wakeup.example.workers.dev") { #expect(AppSettings.serviceURL != nil) }
        withURL("http://wakeup.example.com") { #expect(AppSettings.serviceURL == nil) }
        withURL("not a url") { #expect(AppSettings.serviceURL == nil) }
        withURL("  ") { #expect(AppSettings.serviceURL == nil) }
        withURL(nil) { #expect(AppSettings.serviceURL == nil) }
    }

    @Test func deviceTokenIsStableAndLooksRightForTheProxy() {
        let first = AppSettings.deviceToken
        #expect(first == AppSettings.deviceToken)
        #expect(first.count >= 32 && first.count <= 128)
        #expect(first.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func onPhoneModeNeedsNoKeyAndNoNotice() {
        let defaults = UserDefaults.standard
        let old = defaults.string(forKey: AppSettings.checkMethodKey)
        defer { defaults.set(old, forKey: AppSettings.checkMethodKey) }
        defaults.set(CheckMethod.onPhone.rawValue, forKey: AppSettings.checkMethodKey)
        #expect(Verifiers.isConfigured)
        #expect(!AppSettings.needsPhotoNotice)
        #expect(Verifiers.current() is OfflineVerifier)
    }
}
