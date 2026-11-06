@preconcurrency import AVFoundation
import Observation
import UIKit

/// A live camera that can only take a new photo — there's no way to pick
/// an old one, which is the point. The capture session is only touched on
/// `queue`, which is why the AVFoundation import is `@preconcurrency`.
@MainActor
@Observable
final class CameraModel: NSObject {
    enum State: Equatable {
        case starting
        case running
        case denied
        case unavailable
    }

    private(set) var state: State = .starting
    private(set) var position: AVCaptureDevice.Position = .front
    private(set) var isCapturing = false

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "WakeUp.camera")
    @ObservationIgnored private var pending: CheckedContinuation<Data, Error>?

    enum CameraError: LocalizedError {
        case noPhoto
        var errorDescription: String? { "The camera didn't return a photo. Try again." }
    }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        state = await configure(position) ? .running : .unavailable
    }

    func stop() {
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func flip() async {
        let next: AVCaptureDevice.Position = position == .front ? .back : .front
        if await configure(next) {
            position = next
        }
    }

    func capture() async throws -> Data {
        isCapturing = true
        defer { isCapturing = false }
        let output = output
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            queue.async {
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configure(_ position: AVCaptureDevice.Position) async -> Bool {
        let session = session
        let output = output
        return await withCheckedContinuation { continuation in
            queue.async {
                session.beginConfiguration()
                session.sessionPreset = .photo
                for input in session.inputs {
                    session.removeInput(input)
                }
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input)
                else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addInput(input)
                if !session.outputs.contains(output), session.canAddOutput(output) {
                    session.addOutput(output)
                }
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: true)
            }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        pending?.resume(with: result)
        pending = nil
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let result: Result<Data, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(CameraError.noPhoto)
        }
        Task { @MainActor in
            self.finish(result)
        }
    }
}
