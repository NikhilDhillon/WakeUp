import SwiftUI

/// "12 mornings in a row" with seven small bars for the last seven days.
struct WeekStrip: View {
    let streak: Int
    let days: [(day: Date, mark: DayMark)]
    var calendar: Calendar = .current

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(streak == 1 ? "1 morning in a row" : "\(streak) mornings in a row")
                    .font(.headline)
                Text("Days with no alarm or a skip don't break it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 5) {
                ForEach(days, id: \.day) { item in
                    bar(for: item.mark)
                        .frame(width: typeSize.isAccessibilitySize ? nil : 11, height: 30)
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 11)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: Theme.rowRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func bar(for mark: DayMark) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        switch mark {
        case .passed: shape.fill(Theme.ready)
        case .missed: shape.fill(Theme.warn)
        case .upcoming: shape.strokeBorder(Color.accentColor, lineWidth: 2)
        case .none: shape.fill(Theme.inkSecondary.opacity(0.25))
        }
    }

    private var spokenSummary: String {
        let list = days.map { item -> String in
            let name = calendar.weekdaySymbols[calendar.component(.weekday, from: item.day) - 1]
            switch item.mark {
            case .passed: return "\(name) up"
            case .missed: return "\(name) missed"
            case .upcoming: return "\(name) still to come"
            case .none: return "\(name) no alarm"
            }
        }
        return "\(streak) mornings in a row. Last seven days: " + list.joined(separator: ", ") + ". Opens history."
    }
}

#Preview("Week strip") {
    let cal = Calendar.current
    let marks: [DayMark] = [.passed, .passed, .none, .missed, .passed, .passed, .upcoming]
    let days = marks.enumerated().map { index, mark in
        (day: cal.date(byAdding: .day, value: index - 6, to: .now)!, mark: mark)
    }
    return VStack(spacing: 12) {
        WeekStrip(streak: 12, days: days)
        WeekStrip(streak: 0, days: days.map { ($0.day, .none) })
    }
    .padding()
    .background(Theme.ground)
}

#Preview("Week strip: AX5 dark") {
    let cal = Calendar.current
    let days = (0..<7).map { (day: cal.date(byAdding: .day, value: $0 - 6, to: .now)!, mark: DayMark.passed) }
    return WeekStrip(streak: 7, days: days)
        .padding()
        .background(Theme.ground)
        .environment(\.dynamicTypeSize, .accessibility5)
        .preferredColorScheme(.dark)
}
