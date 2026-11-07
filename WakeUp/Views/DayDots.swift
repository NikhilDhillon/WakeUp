import SwiftUI

/// Seven small circles, one per weekday, in the user's week order. Read-only
/// unless `onToggle` is given, in which case each circle is a button. At
/// accessibility text sizes the circles don't fit, so it falls back to words
/// ("Weekdays"), which are not tappable.
struct DayDots: View {
    let weekdays: Set<Int>
    var calendar: Calendar = .current
    /// Called with the weekday number (1 = Sunday) when a circle is tapped.
    var onToggle: ((Int) -> Void)?

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
        .modifier(SummaryModifier(isInteractive: onToggle != nil && !typeSize.isAccessibilitySize,
                                  label: WakeAlarm.summary(of: weekdays, calendar: calendar)))
    }

    private var order: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    @ViewBuilder
    private func dot(_ weekday: Int) -> some View {
        let on = weekdays.contains(weekday)
        let size: CGFloat = onToggle == nil ? 26 : 34
        let circle = Text(calendar.veryShortWeekdaySymbols[weekday - 1])
            .font(.caption.weight(.semibold))
            .frame(width: size, height: size)
            .background(on ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Theme.inkSecondary.opacity(0.15)), in: Circle())
            .foregroundStyle(on ? Theme.card : Theme.inkSecondary)
        if let onToggle {
            Button { onToggle(weekday) } label: { circle.contentShape(Circle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
        } else {
            circle
        }
    }
}

/// Read-only dots speak as one summary; tappable dots keep their own buttons.
private struct SummaryModifier: ViewModifier {
    let isInteractive: Bool
    let label: String

    func body(content: Content) -> some View {
        if isInteractive {
            content
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        }
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
