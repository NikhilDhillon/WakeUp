import Foundation
import Testing
@testable import WakeUp

struct StrictnessSliderTests {
    @Test func staysInsideFiftyToNinetyFiveInFiveSteps() {
        #expect(StrictnessSlider.clamped(10) == 50)
        #expect(StrictnessSlider.clamped(72) == 70)
        #expect(StrictnessSlider.clamped(73) == 75)
        #expect(StrictnessSlider.clamped(100) == 95)
    }

    @Test func theOldNamedLevelCarriesOver() {
        #expect(StrictnessSlider.percent(saved: nil, legacy: "lenient") == 50)
        #expect(StrictnessSlider.percent(saved: nil, legacy: "normal") == 70)
        #expect(StrictnessSlider.percent(saved: nil, legacy: "strict") == 85)
        #expect(StrictnessSlider.percent(saved: nil, legacy: nil) == 70)
        #expect(StrictnessSlider.percent(saved: nil, legacy: "nonsense") == 70)
        // Once the slider has been saved, it wins.
        #expect(StrictnessSlider.percent(saved: 90, legacy: "lenient") == 90)
    }

    @Test func migrationWritesThePercentOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "StrictnessSliderTests"))
        defaults.removePersistentDomain(forName: "StrictnessSliderTests")
        defaults.set("strict", forKey: AppSettings.strictnessKey)
        StrictnessSlider.migrateIfNeeded(defaults)
        #expect(defaults.integer(forKey: StrictnessSlider.key) == 85)
        // Moving the slider later isn't undone by another launch.
        defaults.set(60, forKey: StrictnessSlider.key)
        StrictnessSlider.migrateIfNeeded(defaults)
        #expect(defaults.integer(forKey: StrictnessSlider.key) == 60)
        defaults.removePersistentDomain(forName: "StrictnessSliderTests")
    }

    @Test func namesFollowTheSlider() {
        #expect(StrictnessSlider.name(for: 50) == "Lenient")
        #expect(StrictnessSlider.name(for: 70) == "Normal")
        #expect(StrictnessSlider.name(for: 85) == "Strict")
        #expect(StrictnessSlider.name(for: 95) == "Very strict")
    }

    @Test func theNamedLevelsKeepTheirOldBars() {
        #expect(StrictnessSlider.thresholds(percent: 85) == Strictness.strict.thresholds)
        #expect(StrictnessSlider.thresholds(percent: 50) == Strictness.lenient.thresholds)
    }

    @Test func theTopOfTheSliderCanStillPass() {
        let top = StrictnessSlider.thresholds(percent: 95)
        // The place check sits 5 above the slider but stops at 97%, not 100%.
        #expect(top.threshold(for: .samePlace) == 0.97)
        #expect(top.threshold(for: .personPresent) == 0.95)
        #expect(top.threshold(for: .appearsAwake) == 0.85)
        // Lower down, the +5 is untouched.
        #expect(abs(StrictnessSlider.thresholds(percent: 85).threshold(for: .samePlace) - 0.90) < 1e-9)
    }
}
