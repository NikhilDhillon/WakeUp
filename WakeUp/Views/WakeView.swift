import SwiftData
import SwiftUI

/// The screen you land on from the ringing alarm. The only way to stop
/// the chain is a live photo the AI accepts, unless there's nothing to
/// check against (no proof or no API key), which gets an honest escape.
struct WakeView: View {
    @State private var coordinator = WakeCoordinator.shared
    @State private var alarmService = AlarmService.shared
    @Query(sort: \Mission.createdAt) private var missions: [Mission]
    @AppStorage(ActiveMission.key) private var activeMissionID = ""
    @State private var showingCamera = false
    @State private var passed = false
    @State private var passedOffline = false

    private var mission: Mission? {
        ActiveMission.resolve(preferred: coordinator.activeSpec?.missionID, fallback: activeMissionID, in: missions)
    }

    private var canCheck: Bool {
        (mission?.isReady ?? false) && Verifiers.isConfigured
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text(coordinator.isFollowUp ? "Still up?" : "Prove you're up")
                .font(.largeTitle.bold())

            VStack(spacing: 12) {
                Image(systemName: coordinator.challenge.symbol)
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text(coordinator.isFollowUp ? "A different challenge this time" : "Today's challenge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(coordinator.challenge.instruction)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }

            missionCard

            Text(remainingText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 12) {
                if canCheck {
                    Button {
                        passed = false
                        passedOffline = false
                        showingCamera = true
                    } label: {
                        Label("Take proof photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text(setupProblem)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(role: .destructive) {
                        coordinator.stopWithoutProof()
                    } label: {
                        Text("Stop alarms without proof")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button("Not yet") {
                    coordinator.notYet()
                }
                .controlSize(.large)
            }
        }
        .padding(24)
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            if passed { coordinator.markPassed(offline: passedOffline) }
        }) {
            if let mission {
                ProofCaptureView(
                    mission: mission,
                    challenge: coordinator.challenge,
                    mode: coordinator.isFollowUp ? .followUp : .wake
                ) { verdict in
                    passed = true
                    passedOffline = verdict.method == .offline
                }
            }
        }
    }

    private var setupProblem: String {
        if !(mission?.isReady ?? false) {
            return "There's no proof set up, so nothing can be checked."
        }
        return "There's no OpenAI key in Settings, so the photo can't be checked."
    }

    @ViewBuilder
    private var missionCard: some View {
        if let mission {
            VStack(alignment: .leading, spacing: 10) {
                Label("Go to: \(mission.name)", systemImage: "location.fill")
                    .font(.headline)
                Text(mission.proofDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mission.orderedPhotos) { photo in
                            if let image = UIImage(data: photo.jpegData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        } else {
            Label("No proof set up yet. Add one from the home screen.", systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var remainingText: String {
        let remaining = coordinator.activeChain.map { chain in
            alarmService.alarms(in: chain).filter { $0.state == .scheduled }.count
        } ?? 0
        switch remaining {
        case 0: return "This is the last alarm in the chain."
        case 1: return "1 more alarm will ring until you pass."
        default: return "\(remaining) more alarms will ring until you pass."
        }
    }
}

#Preview {
    WakeView()
        .modelContainer(for: [Mission.self, ReferencePhoto.self], inMemory: true)
}
