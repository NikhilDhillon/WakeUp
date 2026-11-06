import Foundation

/// How sure the AI must be before a photo counts.
enum Strictness: String, CaseIterable, Identifiable {
    case lenient, normal, strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lenient: "Lenient"
        case .normal: "Normal"
        case .strict: "Strict"
        }
    }

    /// Minimum AI confidence (0–1) for a pass.
    var threshold: Double {
        switch self {
        case .lenient: 0.5
        case .normal: 0.7
        case .strict: 0.85
        }
    }
}

/// App-wide settings. The API key lives in the Keychain; the rest in
/// UserDefaults (views read those with `@AppStorage` and the same keys).
enum AppSettings {
    static let modelKey = "openAIModel"
    static let strictnessKey = "strictness"
    static let defaultModel = "gpt-5-mini"

    private static let keychain = KeychainStore()
    private static let apiKeyAccount = "openai-api-key"

    static var apiKey: String? {
        guard let key = keychain.string(for: apiKeyAccount), !key.isEmpty else { return nil }
        return key
    }

    static var hasAPIKey: Bool { apiKey != nil }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return keychain.set(trimmed, for: apiKeyAccount)
    }

    static func removeAPIKey() {
        keychain.remove(apiKeyAccount)
    }

    static var model: String {
        let stored = UserDefaults.standard.string(forKey: modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultModel : stored
    }

    static var strictness: Strictness {
        UserDefaults.standard.string(forKey: strictnessKey).flatMap(Strictness.init(rawValue:)) ?? .normal
    }
}
