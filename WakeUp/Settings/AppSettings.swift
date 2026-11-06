import Foundation

/// How sure the AI must be about every check before a photo counts.
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

    /// Minimum confidence (0–1) each check needs for a pass.
    var threshold: Double {
        switch self {
        case .lenient: 0.5
        case .normal: 0.7
        case .strict: 0.85
        }
    }
}

extension Strictness {
    /// The bar for each check at this level.
    var thresholds: ProofThresholds { ProofThresholds(base: threshold) }
}

/// Which OpenAI API checks the photo.
enum CheckMethod: String, CaseIterable, Identifiable {
    /// Probabilities per check. Cheaper and faster; no written reason.
    case decisions
    /// The AI also writes a short reason. Slower and pricier.
    case responses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decisions: "Decisions API"
        case .responses: "Responses API"
        }
    }
}

/// App-wide settings. The API key lives in the Keychain; the rest in
/// UserDefaults (views read those with `@AppStorage` and the same keys).
enum AppSettings {
    static let modelKey = "openAIModel"
    static let strictnessKey = "strictness"
    static let checkMethodKey = "checkMethod"
    static let developerModeKey = "developerMode"
    static let offlineBackupKey = "offlineBackup"
    static let keepThumbnailsKey = "keepWakeThumbnails"
    static let defaultModel = "gpt-6-luna"

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

    /// Fall back to the on-phone check when OpenAI can't be reached. On by default.
    static var offlineBackupEnabled: Bool {
        UserDefaults.standard.object(forKey: offlineBackupKey) as? Bool ?? true
    }

    static var model: String {
        let stored = UserDefaults.standard.string(forKey: modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultModel : stored
    }

    static var checkMethod: CheckMethod {
        UserDefaults.standard.string(forKey: checkMethodKey).flatMap(CheckMethod.init(rawValue:)) ?? .decisions
    }

    static var strictness: Strictness {
        UserDefaults.standard.string(forKey: strictnessKey).flatMap(Strictness.init(rawValue:)) ?? .normal
    }
}
