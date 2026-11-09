import SwiftData
import SwiftUI
import UIKit

/// The screen you land on from the ringing alarm ("Bedside"): full white, a
/// huge black challenge and one black button. The only way to stop the chain
/// is a live photo the AI accepts, unless there's nothing to check against
/// (no proof or no way to check), which gets an honest escape.
struct WakeView: View {
    @State private var coordinator = WakeCoordinator.shared
    @State private var alarmService = AlarmService.shared
    @Query(sort: \Mission.createdAt) private var missions: [Mission]
    @AppStorage(ActiveMission.key) private var activeMissionID = ""
    @State private var showingCamera = false
    @State private var showingPhotos = false
    @State private var passed = false
    @State private var passedOffline = false
    @State private var previousBrightness: CGFloat?
    @ScaledMetric(relativeTo: .largeTitle) private var challengeSize = Theme.wakeChallengeSize

    private var mission: Mission? {
        ActiveMission.resolve(preferred: coordinator.activeProofID, fallback: activeMissionID, in: missions)
    }

    private var canCheck: Bool {
        (mission?.isReady ?? false) && Verifiers.isConfigured
    }

    var body: some View {
        // Re-reads the ring number and next ring time every few seconds.
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            content(now: timeline.date)
        }
        .preferredColorScheme(.light)
        .onAppear(perform: raiseBrightness)
        .onDisappear(perform: restoreBrightness)
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            if passed { coordinator.markPassed(offline: passedOffline) }
        }) {
            if let mission {
                ProofCaptureView(
                    mission: mission,
                    challenge: coordinator.challenge,
                    mode: coordinator.isNap ? .nap : (coordinator.isFollowUp ? .followUp : .wake)
                ) { verdict in
                    passed = true
                    passedOffline = verdict.method == .offline
                }
            }
        }
    }

    private func content(now: Date) -> some View {
        let position = coordinator.activeChain?.ringPosition(at: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(topLine(position))
                    .font(.headline)
                    .foregroundStyle(Theme.wakeSecondary)
                    .accessibilityAddTraits(.isHeader)

                Text(coordinator.challenge.instruction)
                    .font(.system(size: challengeSize, weight: .heavy))
                    .foregroundStyle(Theme.wakeInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)

                placeBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .background(Theme.wakeBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            bottomBar(position, now: now)
        }
    }

    private func topLine(_ position: (current: Int, total: Int, next: Date?)?) -> String {
        if coordinator.isNap {
            if coordinator.isFollowUp { return "Still at your desk?" }
            guard let position, position.total > 1, position.current > 1 else { return "Nap's over" }
            return "Nap's over · ring \(position.current) of \(position.total)"
        }
        if coordinator.isFollowUp { return "Still up?" }
        guard let position, position.total > 1 else { return "Prove you're up" }
        return "Ring \(position.current) of \(position.total)"
    }

    // MARK: Place

    @ViewBuilder
    private var placeBlock: some View {
        if let mission {
            VStack(alignment: .leading, spacing: 6) {
                Text(mission.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.wakeInk)
                Text(firstLine(of: mission.proofDescription))
                    .font(.title3)
                    .foregroundStyle(Theme.wakeSecondary)
                if !mission.orderedPhotos.isEmpty {
                    Button(showingPhotos ? "Hide photos" : "Show photos") {
                        withAnimation { showingPhotos.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.wakeInk)
                    .frame(minHeight: Theme.minTapHeight, alignment: .leading)
                    if showingPhotos {
                        photoStrip(mission)
                    }
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            Text("No proof set up yet. Add one from the home screen.")
                .font(.subheadline)
                .foregroundStyle(Theme.wakeSecondary)
        }
    }

    private func photoStrip(_ mission: Mission) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mission.orderedPhotos) { photo in
                    if let image = UIImage(data: photo.jpegData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Reference photo of \(mission.name)")
                    }
                }
            }
        }
    }

    private func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? text
    }

    // MARK: Buttons

    private func bottomBar(_ position: (current: Int, total: Int, next: Date?)?, now: Date) -> some View {
        VStack(spacing: 10) {
            if canCheck {
                Button {
                    passed = false
                    passedOffline = false
                    showingCamera = true
                } label: {
                    Text("Open camera")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.wakeBackground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.wakeInk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text(setupProblem)
                    .font(.footnote)
                    .foregroundStyle(Theme.wakeSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    coordinator.stopWithoutProof()
                } label: {
                    Text("Stop alarms without proof")
                        .font(.headline)
                        .foregroundStyle(Theme.wakeInk)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Theme.wakeInk, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }

            if coordinator.canSnooze(now: now), let nap = coordinator.activeNap {
                snoozeButton(nap)
            }

            Button {
                coordinator.notYet()
            } label: {
                VStack(spacing: 2) {
                    Text("Not yet")
                        .font(.body)
                    Text(nextRingText(position))
                        .font(.footnote)
                }
                .foregroundStyle(Theme.wakeSecondary)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Not yet. \(nextRingText(position))")
            .accessibilityAddTraits(.isButton)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // The buttons stay on screen at the largest text sizes; the challenge above scrolls.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(Theme.wakeBackground)
    }

    /// "Snooze 10 min" with "1 left" under it. The nap rings again from the
    /// first ring when the snooze is up.
    private func snoozeButton(_ nap: NapSession) -> some View {
        let minutes = Int((nap.snoozeLength / 60).rounded())
        let left = nap.snoozesLeft
        return Button {
            Task { await coordinator.snooze() }
        } label: {
            VStack(spacing: 2) {
                Text("Snooze \(minutes) min")
                    .font(.headline)
                Text(left == 1 ? "1 left" : "\(left) left")
                    .font(.footnote)
                    .foregroundStyle(Theme.wakeSecondary)
            }
            .foregroundStyle(Theme.wakeInk)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.wakeInk, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Snooze \(minutes) minutes. \(left) left.")
        .accessibilityAddTraits(.isButton)
    }

    private func nextRingText(_ position: (current: Int, total: Int, next: Date?)?) -> String {
        guard let next = position?.next else { return "This is the last ring" }
        return "Next ring at \(next.formatted(.dateTime.hour().minute()))"
    }

    private var setupProblem: String {
        if !(mission?.isReady ?? false) {
            return "There's no proof set up, so nothing can be checked."
        }
        return "Photos can't be checked yet: add an OpenAI key, a service address or the on-phone check in Settings › Developer tools."
    }

    // MARK: Brightness

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen
    }

    /// Full brightness while the wake screen is up. iOS keeps the value until
    /// the screen locks, so it's put back when the screen goes away.
    private func raiseBrightness() {
        guard let screen, previousBrightness == nil else { return }
        previousBrightness = screen.brightness
        screen.brightness = 1
    }

    private func restoreBrightness() {
        guard let screen, let previous = previousBrightness else { return }
        screen.brightness = previous
        previousBrightness = nil
    }
}

#Preview {
    WakeView()
        .modelContainer(for: [Mission.self, ReferencePhoto.self, WakeAlarm.self, ProofAttempt.self], inMemory: true)
}

#Preview("AX5") {
    WakeView()
        .modelContainer(for: [Mission.self, ReferencePhoto.self, WakeAlarm.self, ProofAttempt.self], inMemory: true)
        .environment(\.dynamicTypeSize, .accessibility5)
}
