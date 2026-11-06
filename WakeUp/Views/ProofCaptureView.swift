import PhotosUI
import SwiftData
import SwiftUI

/// Take a live photo, send it to the AI, and show the result.
/// `.wake` is the real morning check; `.practice` is a dry run from the
/// proof editor that doesn't touch any alarms.
struct ProofCaptureView: View {
    enum Mode {
        case wake
        /// The "Still up?" check after a pass.
        case followUp
        case practice
    }

    let mission: Mission
    let challenge: Challenge
    let mode: Mode
    var onPassed: (Verdict) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.keepThumbnailsKey) private var keepThumbnails = false
    @State private var camera = CameraModel()
    @State private var stage: Stage = .camera
    @State private var cameraError: String?
    #if targetEnvironment(simulator)
    @State private var simulatorPick: PhotosPickerItem?
    #endif

    enum Stage {
        case camera
        case review(Data)
        case checking(Data)
        case result(Data, Verdict)
        case failed(Data, String)
    }

    private var thresholds: ProofThresholds { AppSettings.strictness.thresholds }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .safeAreaInset(edge: .top) { topBar }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .preferredColorScheme(.dark)
    }

    // MARK: Layout

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .camera:
            cameraStage
        case .review(let photo):
            photoStage(photo) {
                HStack(spacing: 16) {
                    Button("Retake") { stage = .camera }
                        .buttonStyle(.bordered)
                    Button {
                        Task { await check(photo) }
                    } label: {
                        Label("Check photo", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
        case .checking(let photo):
            photoStage(photo) {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Checking your photo…")
                }
                .padding()
                .background(.ultraThinMaterial, in: Capsule())
            }
        case .result(let photo, let verdict):
            photoStage(photo) { resultCard(verdict) }
        case .failed(let photo, let message):
            photoStage(photo) {
                VStack(spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Button("Retake") { stage = .camera }
                            .buttonStyle(.bordered)
                        Button("Try again") { Task { await check(photo) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .practice ? "Practice: \(mission.name)" : "Go to: \(mission.name)")
                    .font(.headline)
                Label(challenge.instruction, systemImage: challenge.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var cameraStage: some View {
        switch camera.state {
        case .starting:
            ProgressView().tint(.white)
        case .running:
            ZStack(alignment: .bottom) {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea(edges: .bottom)
                cameraControls
            }
        case .denied:
            message(
                "WakeUp needs the camera to check you're up. Turn it on in Settings > WakeUp > Camera.",
                systemImage: "camera.fill"
            )
        case .unavailable:
            VStack(spacing: 20) {
                message("No camera is available on this device.", systemImage: "camera.badge.ellipsis")
                #if targetEnvironment(simulator)
                PhotosPicker(selection: $simulatorPick, matching: .images) {
                    Label("Simulator only: use a library photo", systemImage: "photo")
                }
                .buttonStyle(.borderedProminent)
                .onChange(of: simulatorPick) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            stage = .review(data)
                        }
                        simulatorPick = nil
                    }
                }
                #endif
            }
        }
    }

    private var cameraControls: some View {
        VStack(spacing: 12) {
            if let cameraError {
                Text(cameraError)
                    .font(.footnote)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            HStack {
                Spacer()
                Button {
                    Task { await takePhoto() }
                } label: {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .background(Circle().fill(.white.opacity(camera.isCapturing ? 0.3 : 0.9)).padding(8))
                        .frame(width: 78, height: 78)
                }
                .disabled(camera.isCapturing)
                .accessibilityLabel("Take photo")
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button {
                    Task { await camera.flip() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title2)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, 28)
                .accessibilityLabel("Switch camera")
            }
        }
        .padding(.bottom, 24)
        .foregroundStyle(.white)
    }

    private func photoStage<Controls: View>(_ photo: Data, @ViewBuilder controls: () -> Controls) -> some View {
        VStack(spacing: 20) {
            if let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            }
            controls()
                .padding(.horizontal)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .foregroundStyle(.white)
    }

    private func resultCard(_ verdict: Verdict) -> some View {
        let problems = verdict.problems(using: thresholds)
        let passed = problems.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            Label(
                passed ? (mode == .practice ? "This would pass" : "You're up!") : "Not yet",
                systemImage: passed ? "checkmark.seal.fill" : "xmark.octagon.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(passed ? .green : .red)

            if verdict.method == .offline {
                Label(
                    passed
                        ? "Checked offline. OpenAI couldn't be reached, so only your face and the place were checked. A follow-up check will come."
                        : "Checked offline, because OpenAI couldn't be reached.",
                    systemImage: "wifi.slash"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
            } else if let reason = verdict.reason {
                Text(reason)
            } else if passed {
                Text("Every check passed.")
            }

            if !passed {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(problems, id: \.self) { problem in
                        Label(problem, systemImage: "minus.circle")
                            .font(.subheadline)
                    }
                }
            }

            Text("Weakest check: \(Int((verdict.overallConfidence * 100).rounded()))% sure")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Weakest check, \(Int((verdict.overallConfidence * 100).rounded())) percent sure")

            if passed {
                Button {
                    onPassed(verdict)
                    dismiss()
                } label: {
                    Text(mode == .practice ? "Done" : "Stop the alarm")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            } else {
                Button {
                    stage = .camera
                } label: {
                    Text("Retake photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle)
            Text(text).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding()
    }

    // MARK: Actions

    private func takePhoto() async {
        do {
            cameraError = nil
            stage = .review(try await camera.capture())
        } catch {
            cameraError = error.localizedDescription
        }
    }

    /// Saves the attempt for the History screen, and counts a failure
    /// against this morning. Practice runs aren't kept.
    private func record(_ verdict: Verdict, seconds: Double, small: Data) {
        guard mode != .practice else { return }
        let passed = verdict.passes(using: thresholds)
        let thumbnail = keepThumbnails ? ImageResizer.jpegData(from: small, maxDimension: 200) : nil
        context.insert(ProofAttempt(
            date: .now,
            kind: mode == .followUp ? .followUp : .wake,
            missionName: mission.name,
            challenge: challenge.instruction,
            verdict: verdict,
            passed: passed,
            duration: seconds,
            thumbnail: thumbnail
        ))
        if !passed { WakeCoordinator.shared.proofFailed() }
    }

    private func check(_ photo: Data) async {
        stage = .checking(photo)
        guard let small = ImageResizer.jpegData(from: photo) else {
            stage = .failed(photo, "Couldn't read the photo. Retake it.")
            return
        }
        let clock = ContinuousClock()
        let started = clock.now
        let request = VerificationRequest(
            photo: small,
            referencePhotos: mission.orderedPhotos.map(\.jpegData),
            description: mission.proofDescription,
            challenge: challenge.instruction,
            capturedAt: .now
        )
        do {
            let verdict = try await Verifiers.current().verify(request)
            let seconds = started.duration(to: clock.now).seconds
            record(verdict, seconds: seconds, small: small)
            stage = .result(photo, verdict)
        } catch {
            stage = .failed(photo, error.localizedDescription)
        }
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
