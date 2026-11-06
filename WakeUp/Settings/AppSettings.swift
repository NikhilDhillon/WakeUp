import Foundation
import Security

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
    /// A WakeUp proxy (see proxy/) that holds the OpenAI key, so no key is needed here.
    case service
    /// Nothing leaves the phone. Weaker: only a face and the right place are checked.
    case onPhone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decisions: "Decisions API"
        case .responses: "Responses API"
        case .service: "WakeUp service"
        case .onPhone: "On this phone only"
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
    static let serviceURLKey = "serviceURL"
    static let photoNoticeKey = "acceptedPhotoNotice"
    static let setupCompletedKey = "hasCompletedSetup"
    static let defaultModel = "gpt-6-luna"

    private static let keychain = KeychainStore()
    private static let apiKeyAccount = "openai-api-key"
    private static let deviceTokenAccount = "device-token"

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

    /// The WakeUp service address, if one is set. Must be https.
    static var serviceURL: URL? {
        let text = UserDefaults.standard.string(forKey: serviceURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    /// A random ID for this install, made once and kept in the Keychain. The
    /// service uses it to count checks per device. It is not a password.
    static var deviceToken: String {
        if let existing = keychain.string(for: deviceTokenAccount), !existing.isEmpty { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        keychain.set(token, for: deviceTokenAccount)
        return token
    }

    /// Whether the user has been told that photos go to OpenAI to be checked.
    static var hasAcceptedPhotoNotice: Bool {
        get { UserDefaults.standard.bool(forKey: photoNoticeKey) }
        set { UserDefaults.standard.set(newValue, forKey: photoNoticeKey) }
    }

    /// True when a check would send the photo off the phone before the
    /// user has agreed to that.
    static var needsPhotoNotice: Bool {
        checkMethod != .onPhone && !hasAcceptedPhotoNotice
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
