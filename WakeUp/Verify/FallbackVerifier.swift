import Foundation

/// Tries the real check, retries once if the network hiccups, and only
/// then falls back to the weaker on-phone check. So no Wi-Fi, an OpenAI
/// outage or used-up credits don't leave you ringing forever.
struct FallbackVerifier: WakeVerifier {
    var primary: WakeVerifier
    var fallback: WakeVerifier
    /// Extra tries after the first one for errors that may pass on their own.
    var retries = 1
    var retryDelay: Duration = .seconds(1)

    func verify(_ request: VerificationRequest) async throws -> Verdict {
        var lastError: VerifierError?
        for attempt in 0...retries {
            do {
                return try await primary.verify(request)
            } catch let error as VerifierError {
                lastError = error
                guard error.isTransient, attempt < retries else { break }
                try await Task.sleep(for: retryDelay)
            }
        }
        guard let lastError, lastError.allowsOfflineBackup else {
            throw lastError ?? VerifierError.unreadableResponse
        }
        do {
            return try await fallback.verify(request)
        } catch {
            // The backup couldn't help; the original problem is what matters.
            throw lastError
        }
    }
}
