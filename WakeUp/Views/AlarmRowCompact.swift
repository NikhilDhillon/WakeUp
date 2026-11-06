import SwiftUI

/// One of the other alarms: time, "Sat, Sun · Kitchen", and an on/off switch.
struct AlarmRowCompact: View {
    @Bindable var alarm: WakeAlarm
    /// The proof's name, or nil for "default place".
    var placeName: String?
    var onEdit: () -> Void
    /// Called just before the on/off switch changes the alarm.
    var willToggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    TimeText(date: alarm.timeOfDay, size: Theme.rowTimeSize, dimmed: !alarm.isEnabled)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("Alarm on", isOn: Binding(
                get: { alarm.isEnabled },
                set: { willToggle(); alarm.isEnabled = $0 }
            ))
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: Theme.minTapHeight)
        .cardBackground(radius: Theme.rowRadius)
        .opacity(alarm.isEnabled ? 1 : 0.55)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        let days = WakeAlarm.summary(of: alarm.weekdays)
        let place = placeName ?? "default place"
        let base = "\(days) · \(place)"
        return alarm.label.isEmpty ? base : "\(alarm.label) · \(base)"
    }
}

#Preview("Rows") {
    let on = WakeAlarm(hour: 9, minute: 0, weekdays: [1, 7])
    let off = WakeAlarm(hour: 5, minute: 30, weekdays: [2, 4, 6])
    off.isEnabled = false
    return VStack(spacing: 8) {
        AlarmRowCompact(alarm: on, placeName: "Kitchen", onEdit: {})
        AlarmRowCompact(alarm: off, placeName: nil, onEdit: {})
    }
    .padding()
    .background(Theme.ground)
}

#Preview("Rows: AX5 dark") {
    let on = WakeAlarm(hour: 9, minute: 0, weekdays: [1, 7])
    return AlarmRowCompact(alarm: on, placeName: "Kitchen", onEdit: {})
        .padding()
        .background(Theme.ground)
        .environment(\.dynamicTypeSize, .accessibility5)
        .preferredColorScheme(.dark)
}
