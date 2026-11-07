import SwiftUI

/// Light or dark for the whole app, or whatever the phone uses. The camera
/// screens stay dark and the wake screen stays white whatever this says.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil follows the phone's setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The saved choice; anything unknown counts as System.
    static func from(_ raw: String) -> AppAppearance {
        AppAppearance(rawValue: raw) ?? .system
    }
}
