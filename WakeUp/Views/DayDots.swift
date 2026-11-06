import SwiftUI

/// Seven small circles, one per weekday, in the user's week order: a
/// read-only version of `WeekdayPicker`. At accessibility text sizes the
/// circles don't fit, so it falls back to words ("Weekdays").
struct DayDots: View {
    let weekdays: Set<Int>
    var calendar: Calendar = .current

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                Text(WakeAlarm.summary(of: weekdays, calendar: calendar))
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(order, id: \.self) { weekday in
                        dot(weekday)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WakeAlarm.summary(of: weekdays, calendar: calendar))
    }

    private var order: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func dot(_ weekday: Int) -> some View {
        let on = weekdays.contains(weekday)
        return Text(calendar.veryShortWeekdaySymbols[weekday - 1])
            .font(.caption2.weight(.semibold))
            .frame(width: 26, height: 26)
            .background(on ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Theme.inkSecondary.opacity(0.15)), in: Circle())
            .foregroundStyle(on ? Theme.card : Theme.inkSecondary)
    }
}

#Preview("Day dots") {
    VStack(alignment: .leading, spacing: 16) {
        DayDots(weekdays: .weekdays)
        DayDots(weekdays: .everyDay)
        DayDots(weekdays: [1, 7])
    }
    .padding()
}

#Preview("Day dots, AX5") {
    DayDots(weekdays: .weekdays)
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
