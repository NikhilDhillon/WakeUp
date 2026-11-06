import SwiftUI

/// Take reference photos of the place with the camera, so you can set up a
/// proof while standing in the room. Each photo is handed back as it's taken.
struct ReferenceCameraView: View {
    var remaining: Int
    var onPhoto: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraModel()
    @State private var taken = 0
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera.state {
            case .starting:
                ProgressView().tint(.white)
            case .running:
                CameraPreview(session: camera.session).ignoresSafeArea()
                VStack {
                    Text(taken == 0 ? "Photograph the place from different angles" : "\(taken) taken. \(max(remaining - taken, 0)) more fit.")
                        .font(.subheadline)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Spacer()
                    HStack(spacing: 40) {
                        Button("Done") { dismiss() }
                            .buttonStyle(.bordered)
                        Button {
                            Task { await shoot() }
                        } label: {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .background(Circle().fill(.white.opacity(camera.isCapturing ? 0.3 : 0.9)).padding(8))
                                .frame(width: 78, height: 78)
                        }
                        .disabled(camera.isCapturing || taken >= remaining)
                        .accessibilityLabel("Take photo")
                        Button {
                            Task { await camera.flip() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2)
                        }
                        .accessibilityLabel("Switch camera")
                    }
                    .padding(.bottom, 24)
                }
                .foregroundStyle(.white)
            case .denied:
                VStack(spacing: 12) {
                    Text("Turn the camera on in Settings > WakeUp.").multilineTextAlignment(.center)
                    Button("Close") { dismiss() }.buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
                .padding()
            case .unavailable:
                VStack(spacing: 12) {
                    Text("No camera is available on this device.")
                    Button("Close") { dismiss() }.buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
            }
        }
        .task {
            await camera.start()
            // Reference photos are of the room, so start on the back camera.
            if camera.state == .running, camera.position == .front { await camera.flip() }
        }
        .onDisappear { camera.stop() }
        .preferredColorScheme(.dark)
    }

    private func shoot() async {
        do {
            error = nil
            let data = try await camera.capture()
            onPhoto(data)
            taken += 1
            if taken >= remaining { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
