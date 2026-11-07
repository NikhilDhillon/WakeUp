import AlarmKit
import AVFoundation
import SwiftData
import SwiftUI
import UserNotifications

/// First-run setup: permissions, how photos are checked, the first proof,
/// a practice run and the first alarm. Every step can be skipped.
///
/// Each page is the same shape: an icon tile, a title, one short line, then
/// the step's card. A dot per step at the top, one big button at the bottom.
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome, permissions, checking, proof, practice, alarm, finish
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Mission.createdAt) private var missions: [Mission]
    @Query private var alarms: [WakeAlarm]
    @AppStorage(AppSettings.checkMethodKey) private var checkMethod = CheckMethod.decisions.rawValue
    @AppStorage(ActiveMission.key) private var activeMissionID = ""

    @State private var alarmService = AlarmService.shared
    @State private var step: Step = .welcome
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var hasKey = AppSettings.hasAPIKey
    @State private var keyDraft = ""
    @State private var showingProofEditor = false
    @State private var showingAlarmEditor = false
    @State private var practicing = false
    @State private var practiceChallenge = Challenge.random()
    /// A practice run was started during this setup.
    @State private var didPractice = false

    private var mission: Mission? { ActiveMission.resolve(id: activeMissionID, in: missions) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    stepContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(.opacity)
            }
            .scrollBounceBehavior(.basedOnSize)
            primaryButton
        }
        .background(Theme.ground.ignoresSafeArea())
        .animation(.snappy, value: step)
        .sheet(isPresented: $showingProofEditor) {
            NavigationStack { MissionEditorView(mission: nil) }
        }
        .sheet(isPresented: $showingAlarmEditor) {
            NavigationStack { AlarmEditorView(alarm: nil) }
        }
        .fullScreenCover(isPresented: $practicing) {
            if let mission {
                ProofCaptureView(mission: mission, challenge: practiceChallenge, mode: .practice)
            }
        }
        .task { await refreshNotificationStatus() }
    }

    // MARK: Frame

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                go(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)
            .accessibilityLabel("Back")

            Spacer()
            StepDots(count: Step.allCases.count, current: step.rawValue)
            Spacer()

            Button("Skip") { dismiss() }
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .opacity(step == .finish ? 0 : 1)
                .disabled(step == .finish)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var primaryButton: some View {
        Button {
            if step == .finish { dismiss() } else { go(by: 1) }
        } label: {
            Text(primaryTitle)
                .font(.headline)
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .finish: "Done"
        default: middleStepTitle(isDone: isStepDone)
        }
    }

    /// Whether what this step asks for has been done (every step can still
    /// be passed over; this only changes the wording).
    private var isStepDone: Bool {
        switch step {
        case .welcome, .finish: true
        case .permissions: alarmService.authorization == .authorized && cameraStatus == .authorized
        case .checking: hasKey
        case .proof: mission?.isReady == true
        case .practice: didPractice
        case .alarm: !alarms.isEmpty
        }
    }

    /// The big button's label on the steps between Welcome and Finish. The
    /// same either way for now; `isDone` is here to word a skipped step
    /// differently (say, "Set up later") if that turns out to help.
    private func middleStepTitle(isDone: Bool) -> String {
        "Continue"
    }

    private func go(by offset: Int) {
        step = Step(rawValue: step.rawValue + offset) ?? (offset > 0 ? .finish : .welcome)
    }

    // MARK: Hero

    private var hero: some View {
        let (symbol, title, text) = heroText
        return VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heroText: (String, String, String) {
        switch step {
        case .welcome:
            ("alarm.fill", "An alarm you can't snooze",
             "WakeUp keeps ringing until a live photo shows you're out of bed.")
        case .permissions:
            ("checkmark.shield.fill", "A few permissions",
             "So WakeUp can ring, see your proof photo and tell you what's next.")
        case .checking:
            ("key.fill", "Your OpenAI key",
             "OpenAI checks each wake-up photo. The photo is sent there and not kept.")
        case .proof:
            ("camera.viewfinder", "Your proof",
             "A place you have to get up for, like the washroom with the light on.")
        case .practice:
            ("hand.thumbsup.fill", "Try it once",
             "Take a practice photo and see what the check says. No alarm involved.")
        case .alarm:
            ("alarm", "Your first alarm",
             "Pick a time and the days. It rings on its own every morning.")
        case .finish:
            ("checkmark.seal.fill", "You're set",
             "Tomorrow it rings until you pass the check. You can run setup again from Settings.")
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeCard
        case .permissions: permissionsCard
        case .checking: keyCard
        case .proof: proofCard
        case .practice: practiceCard
        case .alarm: alarmCard
        case .finish: finishCard
        }
    }

    private var welcomeCard: some View {
        SetupCard {
            HowItWorksRow(number: 1, title: "The alarm rings", detail: "Again and again, a few minutes apart.")
            Divider().padding(.leading, 52)
            HowItWorksRow(number: 2, title: "Prove you're up", detail: "A live photo in your place, doing a quick challenge.")
            Divider().padding(.leading, 52)
            HowItWorksRow(number: 3, title: "It checks the photo", detail: "Only a pass stops the alarm.")
        }
    }

    private var permissionsCard: some View {
        SetupCard {
            PermissionRow(
                symbol: "alarm.fill", title: "Alarms", detail: "Ring even on silent",
                state: permissionState(alarms: alarmService.authorization)
            ) {
                Task { await alarmService.requestAuthorization() }
            }
            Divider().padding(.leading, 56)
            PermissionRow(
                symbol: "camera.fill", title: "Camera", detail: "Take the proof photo",
                state: permissionState(camera: cameraStatus)
            ) {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                    cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                }
            }
            Divider().padding(.leading, 56)
            PermissionRow(
                symbol: "bell.badge.fill", title: "Notifications", detail: "Say when the next ring is",
                state: permissionState(notifications: notificationStatus)
            ) {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                    await refreshNotificationStatus()
                }
            }
        }
    }

    /// Just the OpenAI key: a field and Save, or a tick once it's saved.
    /// (The on-phone check is still in Developer tools.)
    @ViewBuilder
    private var keyCard: some View {
        if hasKey {
            SetupCard {
                HStack(spacing: 14) {
                    Image(systemName: "key.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Key saved").font(.headline)
                        Text("Kept in this iPhone's Keychain")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    DoneMark()
                }
                .padding(16)
            }
        } else {
            SetupCard {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField("sk-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding(14)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("OpenAI key")
                    Button {
                        saveKey()
                    } label: {
                        Text("Save key")
                            .font(.headline)
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                    Text("Create one at platform.openai.com under API keys.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(16)
            }
        }
    }

    private func saveKey() {
        guard AppSettings.setAPIKey(keyDraft) else { return }
        keyDraft = ""
        hasKey = true
        AppSettings.hasAcceptedPhotoNotice = true
        // A key means the OpenAI check, even if the on-phone one was set before.
        if checkMethod == CheckMethod.onPhone.rawValue || checkMethod == CheckMethod.service.rawValue {
            checkMethod = CheckMethod.decisions.rawValue
        }
    }

    @ViewBuilder
    private var proofCard: some View {
        if let mission, mission.isReady {
            SetupCard {
                HStack(spacing: 14) {
                    MissionThumbnail(mission: mission, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mission.name).font(.headline)
                        Text(mission.proofDescription)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    DoneMark()
                }
                .padding(16)
            }
        } else {
            ActionCard(
                symbol: "camera.viewfinder", title: "Create your proof",
                detail: "Describe it and photograph the place from a few angles."
            ) {
                showingProofEditor = true
            }
        }
    }

    @ViewBuilder
    private var practiceCard: some View {
        if mission?.isReady == true, Verifiers.isConfigured {
            ActionCard(
                symbol: "camera.fill", title: "Start a practice run",
                detail: "You'll get a random challenge, like \"hold up 3 fingers\"."
            ) {
                practiceChallenge = .random()
                practicing = true
                didPractice = true
            }
        } else {
            NoteCard(text: "Set up your proof and the photo check first, or continue and try it later from Proofs.")
        }
    }

    @ViewBuilder
    private var alarmCard: some View {
        if let alarm = alarms.first {
            SetupCard {
                HStack(spacing: 14) {
                    TimeText(date: alarm.timeOfDay, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WakeAlarm.summary(of: alarm.weekdays)).font(.headline)
                        Text(AlarmDifficulty.chipText(
                            chainLength: alarm.chainLength, intervalMinutes: alarm.chainIntervalMinutes,
                            followUpMinutes: alarm.followUpMinutes
                        ))
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    DoneMark()
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 12) {
                ActionCard(symbol: "sunrise.fill", title: "7:00 AM on weekdays", detail: "A good place to start.") {
                    context.insert(WakeAlarm(hour: 7, minute: 0, weekdays: .weekdays))
                }
                ActionCard(symbol: "clock", title: "Choose time and days", detail: "Set it exactly how you like.") {
                    showingAlarmEditor = true
                }
            }
        }
    }

    private var finishCard: some View {
        SetupCard {
            ChecklistRow(title: "Alarms allowed", done: alarmService.authorization == .authorized)
            Divider().padding(.leading, 48)
            ChecklistRow(title: "Camera allowed", done: cameraStatus == .authorized)
            Divider().padding(.leading, 48)
            ChecklistRow(title: "OpenAI key saved", done: hasKey)
            Divider().padding(.leading, 48)
            ChecklistRow(title: "Proof ready", done: mission?.isReady == true)
            Divider().padding(.leading, 48)
            ChecklistRow(title: "First alarm set", done: !alarms.isEmpty)
        }
    }

    // MARK: Permission states

    private func permissionState(alarms state: AlarmManager.AuthorizationState) -> PermissionRow.State {
        switch state {
        case .authorized: .allowed
        case .denied: .blocked
        default: .ask
        }
    }

    private func permissionState(camera status: AVAuthorizationStatus) -> PermissionRow.State {
        switch status {
        case .authorized: .allowed
        case .notDetermined: .ask
        default: .blocked
        }
    }

    private func permissionState(notifications status: UNAuthorizationStatus) -> PermissionRow.State {
        switch status {
        case .authorized, .provisional, .ephemeral: .allowed
        case .notDetermined: .ask
        default: .blocked
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// MARK: Pieces

/// One dot per step; the current one is a wider cyan pill.
private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.accentColor : Theme.inkSecondary.opacity(0.3))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// A rounded card on the setup page.
private struct SetupCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
    }
}

private struct HowItWorksRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionRow: View {
    enum State { case ask, allowed, blocked }

    let symbol: String
    let title: String
    let detail: String
    let state: State
    let request: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .allowed:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityLabel("\(title) allowed")
        case .ask:
            Button("Allow", action: request)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
                .background(Color.accentColor, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityLabel("Allow \(title.lowercased())")
        case .blocked:
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) blocked. Open Settings to allow it")
        }
    }
}

/// A tappable card that starts something: icon, title, one line, chevron.
private struct ActionCard: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct NoteCard: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.subheadline)
            .foregroundStyle(Theme.inkSecondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
    }
}

private struct ChecklistRow: View {
    let title: String
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(done ? Color.green : Theme.inkSecondary)
                .frame(width: 24)
            Text(title)
                .font(.body)
                .foregroundStyle(done ? Color.primary : Theme.inkSecondary)
            Spacer(minLength: 0)
            if !done {
                Text("Later")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not yet")
    }
}

private struct DoneMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title2)
            .foregroundStyle(.green)
            .accessibilityLabel("Done")
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: [Mission.self, ReferencePhoto.self, WakeAlarm.self, ProofAttempt.self], inMemory: true)
}
