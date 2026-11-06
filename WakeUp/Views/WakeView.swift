import SwiftUI

/// The screen you land on from the ringing alarm.
/// Phase 1: the camera and AI check aren't built yet, so there's a test
/// button that counts as passing.
struct WakeView: View {
    @State private var coordinator = WakeCoordinator.shared
    @State private var alarmService = AlarmService.shared

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
}
