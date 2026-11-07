import SwiftUI

/// How hard an alarm is to stop: a preset (Gentle, Firm, Relentless) or your
/// own rings, gap and follow-up. Used in the alarm editor and on its own in
/// `DifficultySheet`.
struct DifficultySection: View {
    @Binding var chainLength: Int
    @Binding var intervalMinutes: Int
    @Binding var followUpMinutes: Int
    @State private var showingCustom = false

    var body: some View {
        Section {
            Picker("Difficulty", selection: difficultyBinding) {
                ForEach(difficultyOptions) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if difficulty == .custom || showingCustom {
                Stepper("Rings up to \(chainLength) times", value: $chainLength, in: WakeAlarm.chainLengthRange)
                Stepper("Every \(intervalMinutes) min", value: $intervalMinutes, in: WakeAlarm.chainIntervalRange)
                Picker("Check again after", selection: $followUpMinutes) {
                    Text("Off").tag(0)
                    ForEach(WakeAlarm.followUpChoices.filter { $0 > 0 }, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
            } else {
                Button("Customize") { showingCustom = true }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        } header: {
            Text("Difficulty")
        } footer: {
            Text(difficultyFooter)
        }
    }

    private var difficulty: AlarmDifficulty {
        AlarmDifficulty.matching(chainLength: chainLength, intervalMinutes: intervalMinutes, followUpMinutes: followUpMinutes)
    }

    /// The presets, plus Custom while the values match none of them.
    private var difficultyOptions: [AlarmDifficulty] {
        difficulty == .custom ? AlarmDifficulty.presets + [.custom] : AlarmDifficulty.presets
    }

    private var difficultyBinding: Binding<AlarmDifficulty> {
        Binding(
            get: { difficulty },
            set: { level in
                guard let values = level.values else { return }
                chainLength = values.chainLength
                intervalMinutes = values.intervalMinutes
                followUpMinutes = values.followUpMinutes
            }
        )
    }

    private var difficultyFooter: String {
        AlarmDifficulty.summary(
            chainLength: chainLength, intervalMinutes: intervalMinutes, followUpMinutes: followUpMinutes
        )
    }
}

/// Just an alarm's difficulty, opened from the difficulty chip on Home so
/// you don't have to go through the whole alarm editor.
struct DifficultySheet: View {
    let alarm: WakeAlarm
    @Environment(\.dismiss) private var dismiss
    @State private var chainLength: Int
    @State private var intervalMinutes: Int
    @State private var followUpMinutes: Int

    init(alarm: WakeAlarm) {
        self.alarm = alarm
        _chainLength = State(initialValue: alarm.chainLength)
        _intervalMinutes = State(initialValue: alarm.chainIntervalMinutes)
        _followUpMinutes = State(initialValue: alarm.followUpMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                DifficultySection(
                    chainLength: $chainLength,
                    intervalMinutes: $intervalMinutes,
                    followUpMinutes: $followUpMinutes
                )
            }
            .navigationTitle("\(alarm.timeOfDay.formatted(date: .omitted, time: .shortened)) difficulty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        alarm.chainLength = chainLength
                        alarm.chainIntervalMinutes = intervalMinutes
                        alarm.followUpMinutes = followUpMinutes
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    DifficultySheet(alarm: WakeAlarm(hour: 6, minute: 45))
}
