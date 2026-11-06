import UIKit
import Vision

/// A weaker check that runs on the phone with Apple's Vision framework,
/// for when OpenAI can't be reached:
///
/// - **person_present**: a face is in the photo.
/// - **same_place**: the photo looks like one of your reference photos
///   (how close their image "feature prints" are).
///
/// It can't judge the challenge, your description, whether you look awake
/// or whether it's a photo of a screen, so those aren't part of an offline
/// result. A pass this way always gets a follow-up check later.
struct OfflineVerifier: WakeVerifier {
    /// Feature-print distance at or below this counts as the same place...
    static let sameDistance: Float = 0.45
    /// ...and at or above this as a different one. In between is a blend.
    /// These are starting values; tune them with real photos.
    static let differentDistance: Float = 1.05

    static let checks: Set<ProofCheck> = [.personPresent, .samePlace]

    func verify(_ request: VerificationRequest) async throws -> Verdict {
        try await Task.detached(priority: .userInitiated) {
            try Self.analyze(request)
        }.value
    }

    static func analyze(_ request: VerificationRequest) throws -> Verdict {
        guard !request.referencePhotos.isEmpty else {
            throw VerifierError.offlineCheckFailed("there are no reference photos to compare with.")
        }
        do {
            let faces = try faceCount(in: request.photo)
            let distance = try closestDistance(of: request.photo, to: request.referencePhotos)
            return Verdict(
                probabilities: [
                    .personPresent: faces > 0 ? 0.95 : 0.02,
                    .samePlace: similarity(distance: distance),
                ],
                reason: "Checked on this phone because OpenAI couldn't be reached. It only looked for a face and the right place.",
                method: .offline,
                evaluated: checks
            )
        } catch let error as VerifierError {
            throw error
        } catch {
            throw VerifierError.offlineCheckFailed(error.localizedDescription)
        }
    }

    /// 1 for a near match, 0 for a clear mismatch, linear in between.
    static func similarity(distance: Float) -> Double {
        let span = differentDistance - sameDistance
        let value = 1 - Double((distance - sameDistance) / span)
        return min(max(value, 0), 1)
    }

    static func faceCount(in photo: Data) throws -> Int {
        let request = VNDetectFaceRectanglesRequest()
        #if targetEnvironment(simulator)
        request.usesCPUOnly = true
        #endif
        try VNImageRequestHandler(data: photo, options: [:]).perform([request])
        return request.results?.count ?? 0
    }

    static func featurePrint(of photo: Data) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        #if targetEnvironment(simulator)
        request.usesCPUOnly = true
        #endif
        try VNImageRequestHandler(data: photo, options: [:]).perform([request])
        guard let print = request.results?.first else {
            throw VerifierError.offlineCheckFailed("the photo couldn't be read.")
        }
        return print
    }

    /// The smallest distance between the photo and any reference photo.
    static func closestDistance(of photo: Data, to references: [Data]) throws -> Float {
        let target = try featurePrint(of: photo)
        var best = Float.greatestFiniteMagnitude
        for reference in references {
            var distance: Float = 0
            try target.computeDistance(&distance, to: featurePrint(of: reference))
            best = min(best, distance)
        }
        return best
    }
}
