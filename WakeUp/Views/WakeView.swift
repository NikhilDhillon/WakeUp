import SwiftData
import SwiftUI

/// The screen you land on from the ringing alarm.
/// The camera and AI check (phase 3) aren't built yet, so there's a test
/// button that counts as passing.
struct WakeView: View {
    @State private var coordinator = WakeCoordinator.shared
    @State private var alarmService = AlarmService.shared
    @Query(sort: \Mission.createdAt) private var missions: [Mission]
    @AppStorage(ActiveMission.key) private var activeMissionID = ""

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Prove you're up")
                .font(.largeTitle.bold())

            VStack(spacing: 12) {
                Image(systemName: coordinator.challenge.symbol)
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Today's challenge")
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
                Button {
                    // Phase 3 replaces this with the camera and AI check.
                    coordinator.markPassed()
                } label: {
                    Label("Test: count as passed", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not yet") {
                    coordinator.notYet()
                }
                .controlSize(.large)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var missionCard: some View {
        if let mission = ActiveMission.resolve(id: activeMissionID, in: missions) {
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
        let remaining = alarmService.chainAlarms.filter { $0.state == .scheduled }.count
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
