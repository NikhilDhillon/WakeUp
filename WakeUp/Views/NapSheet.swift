import SwiftData
import SwiftUI

/// Set a nap: how long, which proof ends it, how hard it is to stop and how
/// many snoozes you get. Opens on what you chose last time.
struct NapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Mission.createdAt) private var missions: [Mission]
    @AppStorage(ActiveMission.key) private var activeMissionID = ""

    @State private var minutes: Int
    @State private var isCustomDuration: Bool
    @State private var missionID: String?
    @State private var chainLength: Int
    @State private var intervalMinutes: Int
    @State private var followUpOn: Bool
    @State private var followUpMinutes: Int
    @State private var snoozes: Int
    @State private var snoozeMinutes: Int

    @State private var isStarting = false
    @State private var message: String?
    /// iOS accepted only this many rings; offered as a shorter nap.
    @State private var fit: Int?
    @State private var showingPhotoCheck = false
    @State private var showingNewProof = false
    /// The proofs that existed when "New proof" opened, to find the one just made.
    @State private var proofsBefore: Set<UUID> = []
    @State private var hasPhotoCheck = Verifiers.isConfigured

    init() {
        let saved = NapDefaults.load()
        _minutes = State(initialValue: saved.minutes)
        _isCustomDuration = State(initialValue: !NapSession.quickDurations.contains(saved.minutes))
        _missionID = State(initialValue: saved.missionID)
        _chainLength = State(initialValue: saved.chainLength)
        _intervalMinutes = State(initialValue: saved.intervalMinutes)
        _followUpOn = State(initialValue: saved.followUpMinutes > 0)
        _followUpMinutes = State(initialValue: saved.followUpMinutes > 0 ? saved.followUpMinutes : NapDefaults.relentlessFollowUpMinutes)
        _snoozes = State(initialValue: saved.snoozes)
        _snoozeMinutes = State(initialValue: saved.snoozeMinutes)
    }

    // MARK: Derived

    private var readyMissions: [Mission] { missions.filter(\.isReady) }

    /// The chosen proof if it is ready; otherwise the default proof if it is
    /// ready; otherwise the first ready one.
    private var mission: Mission? {
        if let missionID, let match = readyMissions.first(where: { $0.id.uuidString == missionID }) {
            return match
        }
        if let fallback = ActiveMission.resolve(id: activeMissionID, in: missions), fallback.isReady {
            return fallback
        }
        return readyMissions.first
    }

    private var canStart: Bool {
        mission != nil && hasPhotoCheck && !isStarting
    }

    private var level: AlarmDifficulty {
        AlarmDifficulty.matching(chainLength: chainLength, intervalMinutes: intervalMinutes, followUpMinutes: 0)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                durationSection
                proofSection
                DifficultySection(
                    chainLength: $chainLength,
                    intervalMinutes: $intervalMinutes,
                    followUpMinutes: .constant(0),
                    showsFollowUp: false
                )
                followUpSection
                snoozeSection
                startSection
            }
            .navigationTitle("Nap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Relentless asks "Still at your desk?" by default; the others don't.
            .onChange(of: level) { _, new in
                if AlarmDifficulty.presets.contains(new) { followUpOn = (new == .relentless) }
            }
            .sheet(isPresented: $showingNewProof, onDismiss: selectNewProof) {
                NavigationStack { MissionEditorView(mission: nil) }
            }
            .sheet(isPresented: $showingPhotoCheck, onDismiss: { hasPhotoCheck = Verifiers.isConfigured }) {
                PhotoCheckSheet()
            }
            .alert("Can't start the nap", isPresented: Binding(
                get: { message != nil }, set: { if !$0 { message = nil } }
            )) {
                if let fit {
                    Button("Use \(fit) ring\(fit == 1 ? "" : "s")") { start(chainLength: fit) }
                }
                Button(fit == nil ? "OK" : "Cancel", role: .cancel) { fit = nil }
            } message: {
                Text(message ?? "")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Sections

    private var durationSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(NapSession.quickDurations, id: \.self) { value in
                    chip("\(value) min", selected: !isCustomDuration && minutes == value) {
                        isCustomDuration = false
                        minutes = value
                    }
                }
                chip("Custom", selected: isCustomDuration) { isCustomDuration = true }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if isCustomDuration {
                Picker("Minutes", selection: $minutes) {
                    ForEach(Array(NapSession.durationRange), id: \.self) { value in
                        Text(durationLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }
        } header: {
            Text("Sleep for")
        } footer: {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                Text("Rings at \(timeline.date.addingTimeInterval(Double(minutes) * 60).formatted(date: .omitted, time: .shortened))")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight)
                .foregroundStyle(selected ? Theme.onAccent : Color.primary)
                .background(
                    selected ? Color.accentColor : Color(.secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func durationLabel(_ value: Int) -> String {
        let (h, m) = (value / 60, value % 60)
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }

    private var proofSection: some View {
        Section {
            if missions.isEmpty {
                Text("Make a proof first, for example your desk.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(missions) { item in
                    Button {
                        if item.isReady { missionID = item.id.uuidString }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).foregroundStyle(item.isReady ? Color.primary : .secondary)
                                if !item.isReady {
                                    Text("Needs a description and \(Mission.minPhotos) photos")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if mission?.id == item.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .disabled(!item.isReady)
                    .accessibilityAddTraits(mission?.id == item.id ? .isSelected : [])
                }
            }
            Button {
                proofsBefore = Set(missions.map(\.id))
                showingNewProof = true
            } label: {
                Label("New proof", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Prove you're up at")
        } footer: {
            Text("When the nap rings, only a live photo of you there stops it.")
        }
    }

    private var followUpSection: some View {
        Section {
            Toggle("Still at your desk? check", isOn: $followUpOn)
            if followUpOn {
                Picker("Check again after", selection: $followUpMinutes) {
                    ForEach(NapDefaults.followUpChoices, id: \.self) { Text("\($0) min").tag($0) }
                }
            }
        } footer: {
            Text(followUpOn
                 ? "A few minutes after you pass, it rings again so you can't pass and lie back down."
                 : "Off. Turn it on if you catch yourself passing and lying back down.")
        }
    }

    private var snoozeSection: some View {
        Section {
            Stepper(
                snoozes == 0 ? "No snoozes" : (snoozes == 1 ? "1 snooze" : "\(snoozes) snoozes"),
                value: $snoozes,
                in: NapSession.snoozeCountRange
            )
            Picker("Each snooze", selection: $snoozeMinutes) {
                ForEach(NapSession.snoozeLengthChoices, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(snoozes == 0)
        } header: {
            Text("Snooze")
        } footer: {
            Text(snoozes == 0
                 ? "Stop on the alarm moves to the next ring. Only a photo ends it."
                 : "Stop on the alarm snoozes it, \(snoozes == 1 ? "once" : "\(snoozes) times"). After that, only a photo stops it.")
        }
    }

    private var startSection: some View {
        Section {
            Button {
                start(chainLength: chainLength)
            } label: {
                HStack {
                    Spacer()
                    if isStarting { ProgressView() }
                    Text("Start nap")
                        .font(.headline)
                        .foregroundStyle(canStart ? Theme.onAccent : Color.secondary)
                    Spacer()
                }
                .frame(minHeight: 48)
            }
            .listRowBackground(canStart ? Color.accentColor : Color(.secondarySystemFill))
            .disabled(!canStart)
        } footer: {
            if mission == nil {
                Text("Choose a proof that's ready (a description and \(Mission.minPhotos) photos) to start a nap.")
            } else if !hasPhotoCheck {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Photos can't be checked yet, so a nap couldn't be ended.")
                    Button("Set up the photo check") { showingPhotoCheck = true }
                }
            }
        }
    }

    /// Picks the proof that was just made in the editor, if it saved one.
    private func selectNewProof() {
        let made = missions.filter { !proofsBefore.contains($0.id) }.max { $0.createdAt < $1.createdAt }
        if let made, made.isReady { missionID = made.id.uuidString }
    }

    // MARK: Start

    private func start(chainLength length: Int) {
        guard let mission, !isStarting else { return }
        isStarting = true
        fit = nil
        let followUp = followUpOn ? followUpMinutes : 0
        NapDefaults(
            minutes: minutes, missionID: mission.id.uuidString, chainLength: length,
            intervalMinutes: intervalMinutes, followUpMinutes: followUp,
            snoozes: snoozes, snoozeMinutes: snoozeMinutes
        ).save()

        let nap = NapSession.make(
            now: .now, minutes: minutes, missionID: mission.id.uuidString, proofName: mission.name,
            chainLength: length, chainIntervalMinutes: intervalMinutes, followUpMinutes: followUp,
            snoozes: snoozes, snoozeMinutes: snoozeMinutes
        )
        Task {
            let result = await AlarmService.shared.startNap(nap)
            isStarting = false
            switch result {
            case .started:
                await RingNotice.requestPermissionIfNeeded()
                dismiss()
            case .tooManyAlarms(let allowed):
                fit = allowed
                message = "iOS only has room for \(allowed) more alarm\(allowed == 1 ? "" : "s") right now, and this nap needs \(length)."
            case .failed(let reason):
                message = reason
            }
        }
    }
}

#Preview {
    NapSheet()
        .modelContainer(for: [Mission.self, ReferencePhoto.self, WakeAlarm.self, ProofAttempt.self], inMemory: true)
}
