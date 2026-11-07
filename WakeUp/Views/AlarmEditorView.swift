import SwiftData
import SwiftUI

/// Add or change a wake-up alarm.
struct AlarmEditorView: View {
    let alarm: WakeAlarm?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Mission.createdAt) private var missions: [Mission]

    @State private var time = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? .now
    @State private var weekdays: Set<Int> = .weekdays
    @State private var label = ""
    @State private var missionID = ""
    @State private var chainLength = 10
    @State private var intervalMinutes = 3
    @State private var followUpMinutes = 0
    @State private var sound = AlarmSound.standard.rawValue
    @State private var loaded = false
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }

            Section("Repeat") {
                WeekdayPicker(selection: $weekdays)
                HStack {
                    Button("Weekdays") { weekdays = .weekdays }
                    Spacer()
                    Button("Every day") { weekdays = .everyDay }
                }
                .buttonStyle(.borderless)
                .font(.footnote)
            }

            DifficultySection(
                chainLength: $chainLength,
                intervalMinutes: $intervalMinutes,
                followUpMinutes: $followUpMinutes
            )

            Section {
                TextField("Label (optional)", text: $label)
                Picker("Proof", selection: $missionID) {
                    Text("Default proof").tag("")
                    ForEach(missions) { mission in
                        Text(mission.name).tag(mission.id.uuidString)
                    }
                    if !missionID.isEmpty, !missions.contains(where: { $0.id.uuidString == missionID }) {
                        Text("Deleted proof (using default)").tag(missionID)
                    }
                }
            } footer: {
                if !missionID.isEmpty, !missions.contains(where: { $0.id.uuidString == missionID }) {
                    Text("The proof this alarm used was deleted, so it uses your default proof until you pick another.")
                }
            }

            Section("Sound") {
                Picker("Alarm sound", selection: $sound) {
                    ForEach(AlarmSound.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }

            if alarm != nil {
                Section {
                    Button("Delete alarm", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle(alarm == nil ? "New alarm" : "Edit alarm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(weekdays.isEmpty)
            }
        }
        .confirmationDialog("Delete this alarm?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete alarm", role: .destructive) {
                if let alarm { context.delete(alarm) }
                dismiss()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded, let alarm else { loaded = true; return }
        loaded = true
        time = alarm.timeOfDay
        weekdays = alarm.weekdays
        label = alarm.label
        missionID = alarm.missionID
        chainLength = alarm.chainLength
        intervalMinutes = alarm.chainIntervalMinutes
        followUpMinutes = alarm.followUpMinutes
        sound = alarm.soundRaw
    }

    private func save() {
        let target = alarm ?? WakeAlarm()
        target.timeOfDay = time
        target.weekdays = weekdays
        target.label = label.trimmingCharacters(in: .whitespaces)
        target.missionID = missionID
        target.chainLength = chainLength
        target.chainIntervalMinutes = intervalMinutes
        target.followUpMinutes = followUpMinutes
        target.soundRaw = sound
        if alarm == nil { context.insert(target) }
        dismiss()
    }
}

/// Seven round buttons, one per weekday, in the user's week order.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let on = selection.contains(weekday)
                Button {
                    if on { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Circle())
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

#Preview {
    NavigationStack { AlarmEditorView(alarm: nil) }
        .modelContainer(for: [Mission.self, ReferencePhoto.self, WakeAlarm.self], inMemory: true)
}
