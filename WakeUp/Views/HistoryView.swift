import SwiftData
import SwiftUI

/// Mornings so far: when you were up, how many tries it took, and the streak.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProofAttempt.date, order: .reverse) private var attempts: [ProofAttempt]
    @Query private var alarms: [WakeAlarm]
    @State private var confirmingClear = false

    private var mornings: [MorningSummary] {
        HistoryMath.summaries(of: attempts.map(\.info))
    }

    var body: some View {
        List {
            Section {
                StreakRow(streak: HistoryView.streak(attempts: attempts, alarms: alarms))
            }

            if attempts.isEmpty {
                ContentUnavailableView(
                    "No mornings yet",
                    systemImage: "sun.max",
                    description: Text("Each morning's checks show up here after your first alarm.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(mornings) { morning in
                Section {
                    summaryRow(morning)
                    ForEach(attempts.filter { Calendar.current.isDate($0.date, inSameDayAs: morning.day) }) { attempt in
                        AttemptRow(attempt: attempt)
                    }
                } header: {
                    Text(morning.day, format: .dateTime.weekday(.wide).month().day())
                }
            }

            if !attempts.isEmpty {
                Section {
                    Button("Clear history", role: .destructive) { confirmingClear = true }
                } footer: {
                    Text("Photos aren't kept. Only the times and scores are saved, on this phone.")
                }
            }
        }
        .navigationTitle("History")
        .confirmationDialog("Delete all history?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) {
                for attempt in attempts { context.delete(attempt) }
            }
        }
    }

    private func summaryRow(_ morning: MorningSummary) -> some View {
        HStack {
            if let upAt = morning.upAt {
                Label {
                    Text("Up at \(upAt, format: .dateTime.hour().minute())")
                } icon: {
                    Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                }
            } else {
                Label("Not up", systemImage: "moon.zzz.fill").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(morning.tries == 1 ? "1 try" : "\(morning.tries) tries")
                if morning.followUpTries > 0 {
                    Text(morning.followUpPassed ? "Still up ✓" : "Follow-up not passed")
                        .foregroundStyle(morning.followUpPassed ? .green : .orange)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    static func streak(attempts: [ProofAttempt], alarms: [WakeAlarm], now: Date = .now) -> Int {
        let passDays = Set(attempts.filter { $0.kind == .wake && $0.passed }.map(\.date))
        let weekdays = alarms.filter(\.isEnabled).reduce(into: Set<Int>()) { $0.formUnion($1.weekdays) }
        let skipped = Set(alarms.flatMap(\.skippedDays))
        return HistoryMath.streak(passDays: passDays, alarmWeekdays: weekdays, skippedDays: skipped, now: now)
    }
}

struct StreakRow: View {
    let streak: Int

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(streak == 1 ? "1 morning in a row" : "\(streak) mornings in a row")
                    .font(.headline)
                Text("Days with no alarm or a skip don't break it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "flame.fill")
                .foregroundStyle(streak > 0 ? .orange : .gray)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AttemptRow: View {
    let attempt: ProofAttempt

    var body: some View {
        DisclosureGroup {
            ForEach(attempt.confidences, id: \.check) { item in
                LabeledContent(item.check.title, value: item.value.formatted(.percent.precision(.fractionLength(0))))
                    .font(.footnote)
            }
            LabeledContent("Challenge", value: attempt.challenge).font(.footnote)
            LabeledContent("Proof", value: attempt.missionName).font(.footnote)
            LabeledContent("Checked with", value: attempt.method.title).font(.footnote)
            LabeledContent("Took", value: String(format: "%.1f s", attempt.durationSeconds)).font(.footnote)
            if attempt.inputTokens > 0 {
                LabeledContent("Input tokens", value: attempt.inputTokens.formatted()).font(.footnote)
            }
            if let data = attempt.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Thumbnail of the photo")
            }
        } label: {
            HStack {
                Image(systemName: attempt.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(attempt.passed ? .green : .red)
                Text(attempt.date, format: .dateTime.hour().minute())
                Text(attempt.kind == .followUp ? "Still up?" : "Wake")
                    .foregroundStyle(.secondary)
                if attempt.method == .offline {
                    Text("Offline")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .contain)
    }
}
