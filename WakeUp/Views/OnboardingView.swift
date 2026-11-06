import AVFoundation
import SwiftData
import SwiftUI

/// First-run setup: permissions, how photos are checked, the first proof,
/// a practice run and the first alarm. Every step can be skipped.
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
    @State private var hasKey = AppSettings.hasAPIKey
    @State private var keyDraft = ""
    @State private var showingProofEditor = false
    @State private var showingAlarmEditor = false
    @State private var practicing = false
    @State private var practiceChallenge = Challenge.random()

    private var mission: Mission? { ActiveMission.resolve(id: activeMissionID, in: missions) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                    .padding(.horizontal)
                    .accessibilityLabel("Setup progress")
                ScrollView {
                    content
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                controls
            }
            .navigationTitle("Set up WakeUp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip setup") { dismiss() }
                }
            }
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
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            page("alarm.fill", "An alarm that wants proof",
                 "WakeUp keeps ringing until you take a live photo that shows you're out of bed: in the right place, doing a random challenge like \"hold up 3 fingers\". An AI checks it. Setup takes a few minutes.")
        case .permissions:
            page("bell.badge", "Two permissions",
                 "WakeUp needs to set alarms and use the camera.")
            VStack(alignment: .leading, spacing: 12) {
                if alarmService.authorization == .authorized {
                    Label("Alarms allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Allow alarms") { Task { await alarmService.requestAuthorization() } }
                        .buttonStyle(.borderedProminent)
                }
                if cameraStatus == .authorized {
                    Label("Camera allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if cameraStatus == .notDetermined {
                    Button("Allow camera") {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("Camera blocked. Turn it on in Settings > WakeUp.", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }
        case .checking:
            page("sparkles", "How photos are checked",
                 "To check your photo, WakeUp sends it with your reference photos to OpenAI. WakeUp doesn't keep the photo. Or choose the on-phone check, which sends nothing but only checks for a face and the right place.")
            VStack(alignment: .leading, spacing: 12) {
                if checkMethod == CheckMethod.onPhone.rawValue {
                    Label("Using the on-phone check", systemImage: "iphone").foregroundStyle(.green)
                    Button("Use OpenAI instead") { checkMethod = CheckMethod.decisions.rawValue }
                } else if hasKey {
                    Label("OpenAI key saved on this iPhone", systemImage: "key.fill").foregroundStyle(.green)
                } else {
                    SecureField("OpenAI key (sk-…)", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key and agree") {
                        if AppSettings.setAPIKey(keyDraft) {
                            keyDraft = ""
                            hasKey = true
                            AppSettings.hasAcceptedPhotoNotice = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Use the on-phone check instead") { checkMethod = CheckMethod.onPhone.rawValue }
                    Text("Create a key at platform.openai.com under API keys. It stays in the iPhone Keychain.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        case .proof:
            page("camera.viewfinder", "Your proof",
                 "Describe what proves you're up, like \"me sitting in the washroom with the light on\", and photograph the place from a few angles. You can take the photos right now.")
            if let mission {
                Label("\(mission.name) is ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Create your proof") { showingProofEditor = true }
                    .buttonStyle(.borderedProminent)
            }
        case .practice:
            page("hand.thumbsup", "Try it once",
                 "Take a practice photo to see what the AI says. It doesn't touch any alarm.")
            if mission?.isReady == true, Verifiers.isConfigured {
                Button("Start a practice run") {
                    practiceChallenge = .random()
                    practicing = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Finish the proof and the photo checking first, or skip this.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .alarm:
            page("alarm", "Your first alarm",
                 "Pick a time and the days. It rings every morning on its own until you prove you're up.")
            if let alarm = alarms.first {
                Label("\(alarm.timeOfDay.formatted(date: .omitted, time: .shortened)), \(WakeAlarm.summary(of: alarm.weekdays))",
                      systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Add a 7:00 weekday alarm") {
                        context.insert(WakeAlarm(hour: 7, minute: 0, weekdays: .weekdays))
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Choose time and days") { showingAlarmEditor = true }
                }
            }
        case .finish:
            page("checkmark.seal.fill", "You're set",
                 "Tomorrow morning it rings until you pass the check. Open the app each evening or so; it also tops up the next mornings by itself. You can run this setup again from Settings.")
        }
    }

    private func page(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
            Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack {
            if step != .welcome {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
            }
            Spacer()
            if step == .finish {
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            } else {
                Button(step == .welcome ? "Start" : "Next") {
                    step = Step(rawValue: step.rawValue + 1) ?? .finish
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .padding()
        .background(.regularMaterial)
    }
}
