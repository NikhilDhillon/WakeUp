import AlarmKit
import AVFoundation
import SwiftData
import SwiftUI

/// Home: your alarms, your proof, and anything that needs setting up.
struct HomeView: View {
    @State private var alarmService = AlarmService.shared
    @State private var coordinator = WakeCoordinator.shared
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\WakeAlarm.hour), SortDescriptor(\WakeAlarm.minute)]) private var alarms: [WakeAlarm]
    @Query(sort: \Mission.createdAt) private var missions: [Mission]
    @Query private var attempts: [ProofAttempt]
    @AppStorage(ActiveMission.key) private var activeMissionID = ""
    @State private var showingSettings = false
    @State private var hasAPIKey = AppSettings.hasAPIKey
    @State private var editing: AlarmEditorTarget?
    @State private var skipMessage: String?
    @State private var showingSetup = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @AppStorage(AppSettings.setupCompletedKey) private var setupCompleted = false

    var body: some View {
        NavigationStack {
            List {
                permissionSection
                warningsSection
                alarmsSection
                proofSection
                Section("History") {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        StreakRow(streak: HistoryView.streak(attempts: attempts, alarms: alarms))
                    }
                    if let lastPassed = coordinator.lastPassed {
                        Label {
                            Text("Last proof: \(lastPassed, format: .dateTime.weekday(.wide).hour().minute())")
                        } icon: {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                    }
                }
                if let error = alarmService.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("WakeUp")
            .refreshable { await syncAlarms() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = .new
                    } label: {
                        Label("Add alarm", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                hasAPIKey = AppSettings.hasAPIKey
            }) {
                SettingsView(onRunSetup: { showingSetup = true })
            }
            .fullScreenCover(isPresented: $showingSetup, onDismiss: { setupCompleted = true }) {
                OnboardingView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .sheet(item: $editing) { target in
                NavigationStack {
                    switch target {
                    case .new:
                        AlarmEditorView(alarm: nil)
                    case .existing(let alarm):
                        AlarmEditorView(alarm: alarm)
                    }
                }
            }
            .alert("Can't skip", isPresented: Binding(get: { skipMessage != nil }, set: { if !$0 { skipMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(skipMessage ?? "")
            }
            // Keep AlarmKit in step with the alarms whenever one changes.
            .onChange(of: alarms.map(\.spec)) { _, _ in
                Task { await syncAlarms() }
            }
            .task {
                // Brand-new installs get the setup flow; anyone with data already doesn't.
                if !setupCompleted {
                    if missions.isEmpty && alarms.isEmpty && !AppSettings.hasAPIKey {
                        showingSetup = true
                    } else {
                        setupCompleted = true
                    }
                }
                await syncAlarms()
            }
        }
    }

    // MARK: Sections

    /// Things that could stop tomorrow's alarm, in plain words.
    @ViewBuilder
    private var warningsSection: some View {
        let warnings = HealthCheck.warnings(healthInputs)
        if !warnings.isEmpty {
            Section("Heads up") {
                ForEach(warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var healthInputs: HealthInputs {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return HealthInputs(
            alarmsAllowed: alarmService.authorization != .denied,
            hasEnabledAlarm: alarms.contains(where: \.isEnabled),
            lowPowerMode: lowPower,
            batteryLevel: UIDevice.current.batteryLevel,
            isCharging: UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full,
            daysSinceInstall: Self.daysSinceInstall(),
            hasProof: activeMission?.isReady ?? false,
            canCheckPhoto: Verifiers.isConfigured,
            cameraDenied: AVCaptureDevice.authorizationStatus(for: .video) == .denied
        )
    }

    /// Days since a development build was installed. nil for builds that
    /// don't expire (App Store and TestFlight builds have no embedded profile).
    private static func daysSinceInstall() -> Int? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil,
              let created = (try? FileManager.default.attributesOfItem(atPath: Bundle.main.bundlePath))?[.creationDate] as? Date
        else { return nil }
        return Calendar.current.dateComponents([.day], from: created, to: .now).day
        #endif
    }

    private var permissionSection: some View {
        Group {
            switch alarmService.authorization {
            case .authorized:
                EmptyView()
            case .denied:
                Section {
                    Label("Alarms blocked. Turn them on in Settings > WakeUp.", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            case .notDetermined:
                Section {
                    Button("Allow alarms") {
                        Task { await alarmService.requestAuthorization() }
                    }
                }
            @unknown default:
                EmptyView()
            }
        }
    }

    private var alarmsSection: some View {
        Section {
            if alarms.isEmpty {
                ContentUnavailableView {
                    Label("No alarms yet", systemImage: "alarm")
                } description: {
                    Text("Set the time and the days once. It rings every morning on its own until you prove you're up.")
                } actions: {
                    Button("Add an alarm") { editing = .new }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
            ForEach(alarms) { alarm in
                AlarmRow(
                    alarm: alarm,
                    onEdit: { editing = .existing(alarm) },
                    onToggleSkip: { toggleSkip(alarm) }
                )
            }
            .onDelete { offsets in
                for index in offsets { context.delete(alarms[index]) }
            }
        } header: {
            Text("Alarms")
        } footer: {
            if !alarms.isEmpty {
                Text("Mornings are scheduled a few days ahead, so the alarm rings even if you don't open the app.")
            }
        }
    }

    private var activeMission: Mission? {
        ActiveMission.resolve(id: activeMissionID, in: missions)
    }

    private var proofSection: some View {
        Section {
            NavigationLink {
                MissionsView()
            } label: {
                if let mission = activeMission {
                    HStack(spacing: 12) {
                        MissionThumbnail(mission: mission, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mission.name).font(.headline)
                            Text(mission.proofDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Label("Set up your proof", systemImage: "camera.viewfinder")
                }
            }
            if !Verifiers.isConfigured {
                Button {
                    showingSettings = true
                } label: {
                    Label("Add your OpenAI key to turn on the AI check", systemImage: "key")
                }
            }
        } header: {
            Text("Default proof")
        } footer: {
            if activeMission == nil {
                Text("Describe what proves you're up and add a few photos of the place.")
            } else {
                Text("Alarms use this proof unless you pick another one for them.")
            }
        }
    }

    // MARK: Actions

    private func syncAlarms() async {
        // Forget skipped days that are long past.
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        for alarm in alarms where alarm.skippedDays.contains(where: { $0 < cutoff }) {
            alarm.skippedDays.removeAll { $0 < cutoff }
        }
        await alarmService.update(specs: alarms.map(\.spec))
    }

    private func toggleSkip(_ alarm: WakeAlarm) {
        let spec = alarm.spec
        guard let occurrence = SchedulePlanner.skippableOccurrence(of: spec, after: .now) else { return }
        let calendar = Calendar.current
        if let index = alarm.skippedDays.firstIndex(where: { calendar.isDate($0, inSameDayAs: occurrence.day) }) {
            alarm.skippedDays.remove(at: index)
            return
        }
        switch SkipPolicy.check(day: occurrence.day, skipped: alarm.skippedDays, now: .now) {
        case .allowed:
            alarm.skippedDays.append(occurrence.day)
        case .tooSoon:
            skipMessage = "Skipping has to be done the day before."
        case .weekLimit:
            skipMessage = "You can skip at most \(SkipPolicy.maxPerWeek) days in any week."
        }
    }
}

enum AlarmEditorTarget: Identifiable {
    case new
    case existing(WakeAlarm)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let alarm): alarm.id.uuidString
        }
    }
}

/// One alarm in the list: the time, the days, an on/off switch and the
/// "Skip" button for the next morning.
private struct AlarmRow: View {
    @Bindable var alarm: WakeAlarm
    var onEdit: () -> Void
    var onToggleSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alarm.timeOfDay, format: .dateTime.hour().minute())
                            .font(.system(.largeTitle, design: .rounded, weight: .light))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Toggle("Alarm on", isOn: $alarm.isEnabled)
                    .labelsHidden()
            }
            if alarm.isEnabled, let skippable = SchedulePlanner.skippableOccurrence(of: alarm.spec, after: .now) {
                let skipping = alarm.skippedDays.contains { Calendar.current.isDate($0, inSameDayAs: skippable.day) }
                HStack {
                    if let next = SchedulePlanner.nextRing(of: alarm.spec, after: .now) {
                        Label {
                            Text("Next: \(next, format: .dateTime.weekday(.abbreviated).hour().minute())")
                        } icon: {
                            Image(systemName: "bell")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(skipping ? "Undo skip" : "Skip \(skippable.day.formatted(.dateTime.weekday(.abbreviated)))") {
                        onToggleSkip()
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(alarm.isEnabled ? 1 : 0.55)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        let days = WakeAlarm.summary(of: alarm.weekdays)
        return alarm.label.isEmpty ? days : "\(alarm.label), \(days)"
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Mission.self, ReferencePhoto.self, WakeAlarm.self, ProofAttempt.self], inMemory: true)
}
