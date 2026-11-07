import Foundation

/// Everything the AI needs to judge one proof photo.
struct VerificationRequest: Sendable {
    var photo: Data
    var referencePhotos: [Data]
    var description: String
    var challenge: String
    var capturedAt: Date
}

/// Anything that can judge a proof photo. OpenAI today; another model
/// (or one running on the phone) can be swapped in later.
protocol WakeVerifier: Sendable {
    func verify(_ request: VerificationRequest) async throws -> Verdict
}

enum VerifierError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited(String)
    case badRequest(String)
    case server(Int)
    case refused(String)
    case incomplete(String)
    case unreadableResponse
    case network(String)
    /// The on-phone backup couldn't check the photo either.
    case offlineCheckFailed(String)

    /// Worth trying again straight away.
    var isTransient: Bool {
        switch self {
        case .network, .server, .incomplete, .unreadableResponse: true
        default: false
        }
    }

    /// OpenAI can't help right now, so the on-phone check may step in.
    var allowsOfflineBackup: Bool {
        switch self {
        case .network, .server, .rateLimited, .invalidAPIKey, .incomplete, .unreadableResponse: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your OpenAI key in Settings › Developer tools to turn on the AI check."
        case .invalidAPIKey:
            "OpenAI didn't accept the API key. Check it in Settings › Developer tools."
        case .rateLimited(let message):
            "OpenAI is limiting requests or your credits ran out. \(message)"
        case .badRequest(let message):
            "OpenAI rejected the request: \(message)"
        case .server(let status):
            "OpenAI had a problem (error \(status)). Try again."
        case .refused(let message):
            "The AI declined to check this photo: \(message)"
        case .incomplete(let reason):
            "The AI's answer was cut off (\(reason)). Try again."
        case .unreadableResponse:
            "Couldn't read the AI's answer. Try again."
        case .network(let message):
            "Couldn't reach OpenAI: \(message)"
        case .offlineCheckFailed(let message):
            "Couldn't check the photo on this phone: \(message)"
        }
    }
}

enum Verifiers {
    /// Whether `current()` can actually check a photo.
    static var isConfigured: Bool {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "WakeUpMockVerdict") != nil { return true }
        #endif
        switch AppSettings.checkMethod {
        case .decisions, .responses: return AppSettings.hasAPIKey
        case .service: return AppSettings.serviceURL != nil
        case .onPhone: return true
        }
    }

    /// The verifier the app uses right now.
    static func current() -> WakeVerifier {
        #if DEBUG
        // For testing the flow without a key: launch with
        // `-WakeUpMockVerdict pass` (or `fail`).
        if let mock = UserDefaults.standard.string(forKey: "WakeUpMockVerdict") {
            return MockVerifier(passes: mock == "pass")
        }
        #endif
        let primary: WakeVerifier
        switch AppSettings.checkMethod {
        case .decisions:
            primary = DecisionsVerifier(apiKey: AppSettings.apiKey)
        case .responses:
            primary = ResponsesVerifier(apiKey: AppSettings.apiKey, model: AppSettings.model)
        case .service:
            guard let base = AppSettings.serviceURL else { return OfflineVerifier() }
            primary = DecisionsVerifier(
                apiKey: AppSettings.deviceToken,
                endpoint: base.appending(path: "v1/decisions")
            )
        case .onPhone:
            return OfflineVerifier()
        }
        guard AppSettings.offlineBackupEnabled else { return primary }
        return FallbackVerifier(primary: primary, fallback: OfflineVerifier())
    }
}

#if DEBUG
/// Answers after a short pause without calling any AI.
struct MockVerifier: WakeVerifier {
    var passes: Bool

    func verify(_ request: VerificationRequest) async throws -> Verdict {
        try await Task.sleep(for: .seconds(1.5))
        return Verdict(
            probabilities: [
                .samePlace: 0.95,
                .personPresent: passes ? 0.97 : 0.08,
                .matchesDescription: passes ? 0.91 : 0.2,
                .challengeCompleted: passes ? 0.88 : 0.05,
                .appearsAwake: 0.9,
                .screenOrPrint: 0.03,
            ],
            reason: nil
        )
    }
}
#endif
