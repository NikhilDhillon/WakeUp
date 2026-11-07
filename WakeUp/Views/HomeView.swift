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
    /// The alarm whose difficulty is being changed from the card's chip.
    @State private var editingDifficulty: WakeAlarm?
    @State private var skipMessage: String?
    @State private var showingSetup = false
    @State private var showingPlaces = false
    @State private var showingHistory = false
    @State private var showingStatusDetails = false
    /// The photo check on its own, from the "Photo check isn't set up" banner.
    @State private var showingPhotoCheck = false
    /// Ticks every minute so "next alarm" stays right while the app is open.
    @State private var now = Date.now
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The alarm the card stays on after a switch is flipped. Without it,
    /// turning the card's alarm off swaps in the next alarm (still on) and
    /// turning another on pulls it up into the card, so the switch looks
    /// like it did nothing. Let go the next time Home is shown fresh.
    @State private var heldCardID: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.setupCompletedKey) private var setupCompleted = false

    var body: some View {
        NavigationStack {
            List {
                if let status {
                    StatusPill(
                        status: status,
                        onAction: perform,
                        onShowAll: { showingStatusDetails = true }
                    )
                    .plainRow(top: 4)
                }

                if let cardPick, let alarm = alarms.first(where: { $0.id == cardPick.alarmID }) {
                    NextAlarmCard(
                        alarm: alarm,
                        mission: mission(for: alarm),
                        ring: cardPick.ring,
                        onEdit: { editing = .existing(alarm) },
                        onOpenPlace: { showingPlaces = true },
                        onToggleSkip: { toggleSkip(alarm) },
                        willToggle: holdCard,
                        onEditDifficulty: { editingDifficulty = alarm }
                    )
                    .plainRow(top: 6, bottom: 8)
                } else {
                    emptyCard.plainRow(top: 6, bottom: 8)
                }

                if !otherAlarms.isEmpty {
                    Text("Other alarms")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .accessibilityAddTraits(.isHeader)
                        .plainRow(top: 10, bottom: 0)

                    ForEach(otherAlarms) { alarm in
                        AlarmRowCompact(
                            alarm: alarm,
                            placeName: namedPlace(for: alarm)?.name,
                            onEdit: { editing = .existing(alarm) },
                            willToggle: holdCard
                        )
                        .plainRow()
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(otherAlarms[index]) }
                    }
                }

                if !alarms.isEmpty {
                    Button { showingHistory = true } label: {
                        WeekStrip(streak: streak, days: recentDays)
                    }
                    .buttonStyle(.plain)
                    .plainRow(top: 14, bottom: 24)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Alarms")
            .refreshable {
                heldCardID = nil
                await syncAlarms()
            }
            .navigationDestination(isPresented: $showingPlaces) { MissionsView() }
            .navigationDestination(isPresented: $showingHistory) { HistoryView() }
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
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.onAccent)
                    }
                    .accessibilityLabel("Add alarm")
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
            }
            .sheet(isPresented: $showingStatusDetails) {
                if let status {
                    StatusDetailsSheet(status: status, onAction: perform)
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                hasAPIKey = AppSettings.hasAPIKey
            }) {
                SettingsView(onRunSetup: { showingSetup = true })
            }
            .sheet(item: $editingDifficulty) { alarm in
                DifficultySheet(alarm: alarm)
            }
            .sheet(isPresented: $showingPhotoCheck, onDismiss: {
                hasAPIKey = AppSettings.hasAPIKey
            }) {
                PhotoCheckSheet()
            }
            .fullScreenCover(isPresented: $showingSetup, onDismiss: { setupCompleted = true }) {
                OnboardingView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
            .sheet(item: $editing, onDismiss: { heldCardID = nil }) { target in
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
            .onChange(of: alarms.count) { _, _ in heldCardID = nil }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { heldCardID = nil }
            }
            .task {
                #if DEBUG
                DebugSeed.run(in: context)
                #endif
                removeOldPresetFollowUps()
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

    // MARK: Derived state

    private var specs: [AlarmSpec] { alarms.map(\.spec) }

    /// The alarm that really rings next (for the status pill).
    private var pick: NextUp.Pick? { NextUp.pick(specs: specs, now: now) }

    /// The alarm the card shows: the next one, unless a switch flip is holding it.
    private var cardPick: NextUp.Pick? { NextUp.pick(specs: specs, now: now, holding: heldCardID) }

    private var otherAlarms: [WakeAlarm] {
        alarms.filter { $0.id != cardPick?.alarmID }
    }

    /// Keeps the card on whatever it shows now while a switch is flipped.
    private func holdCard() {
        if heldCardID == nil { heldCardID = cardPick?.alarmID }
    }

    private var status: HomeStatus? {
        HomeStatus.make(
            warnings: HealthCheck.warnings(healthInputs),
            lastError: alarmService.lastError,
            authorizationNotDetermined: alarmService.authorization == .notDetermined,
            hasAlarms: !alarms.isEmpty,
            hasEnabledAlarm: alarms.contains(where: \.isEnabled),
            nextRing: pick?.ring,
            now: now
        )
    }

    private var streak: Int {
        HistoryView.streak(attempts: attempts, now: now)
    }

    /// Past days from what happened; only today looks at your alarms.
    private var recentDays: [(day: Date, mark: DayMark)] {
        HistoryMath.recentDays(
            passDays: HistoryView.passDays(attempts),
            missedDays: ScheduleStore().missedDays,
            todayHasAlarm: todayHasAlarm,
            now: now
        )
    }

    /// An alarm that's on, set for today and not skipped today.
    private var todayHasAlarm: Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        return alarms.contains { alarm in
            alarm.isEnabled && alarm.weekdays.contains(weekday)
                && !alarm.skippedDays.contains { calendar.isDate($0, inSameDayAs: now) }
        }
    }

    private var activeMission: Mission? {
        ActiveMission.resolve(id: activeMissionID, in: missions)
    }

    /// The proof an alarm uses: its own, or the default.
    private func mission(for alarm: WakeAlarm) -> Mission? {
        ActiveMission.resolve(
            preferred: alarm.missionID.isEmpty ? nil : alarm.missionID, fallback: activeMissionID, in: missions
        )
    }

    /// The alarm's own proof, or nil when it uses the default.
    private func namedPlace(for alarm: WakeAlarm) -> Mission? {
        missions.first { $0.id.uuidString == alarm.missionID }
    }

    // MARK: Pieces

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "alarm")
                .font(.largeTitle)
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityHidden(true)
            Text("Set your first alarm")
                .font(.title3.weight(.semibold))
            Text("Set the time and the days once. It rings every morning on its own until you prove you're up.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Button {
                editing = .new
            } label: {
                Label("Add an alarm", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.card)
                .cardShadow()
        }
    }

    /// What the status pill's button does.
    private func perform(_ action: StatusAction) {
        switch action {
        case .retry:
            Task { await syncAlarms() }
        case .openSystemSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .chooseProof:
            showingPlaces = true
        case .setUpPhotoCheck:
            showingPhotoCheck = true
        case .showDetails:
            showingStatusDetails = true
        case .requestAuthorization:
            Task { await alarmService.requestAuthorization() }
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
            daysUntilBuildExpires: BuildExpiry.daysLeftForThisBuild(now: now),
            hasProof: activeMission?.isReady ?? false,
            canCheckPhoto: Verifiers.isConfigured,
            cameraDenied: AVCaptureDevice.authorizationStatus(for: .video) == .denied
        )
    }

    // MARK: Actions

    /// Firm and Relentless used to include a "Still up?" follow-up; they
    /// don't any more. Once, turn it off on alarms still set exactly to the
    /// old versions, so they keep matching their preset.
    private func removeOldPresetFollowUps() {
        let key = "removedPresetFollowUps"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for alarm in alarms {
            alarm.followUpMinutes = AlarmDifficulty.followUpAfterPresetChange(
                chainLength: alarm.chainLength,
                intervalMinutes: alarm.chainIntervalMinutes,
                followUpMinutes: alarm.followUpMinutes
            )
        }
        UserDefaults.standard.set(true, forKey: key)
    }

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

extension View {
    /// A list row with no separator or background, padded to the screen margin.
    func plainRow(top: CGFloat = 4, bottom: CGFloat = 4) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: Theme.screenMargin, bottom: bottom, trailing: Theme.screenMargin))
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Mission.self, ReferencePhoto.self, WakeAlarm.self, ProofAttempt.self], inMemory: true)
}
