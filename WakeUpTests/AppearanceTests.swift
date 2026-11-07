import SwiftUI
import Testing
@testable import WakeUp

struct AppearanceTests {
    @Test func eachChoiceMapsToItsScheme() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test func unknownOrMissingValuesFollowThePhone() {
        #expect(AppAppearance.from("") == .system)
        #expect(AppAppearance.from("sepia") == .system)
        #expect(AppAppearance.from("dark") == .dark)
    }
}
