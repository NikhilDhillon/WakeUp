import AlarmKit
import SwiftUI

/// Tools for trying the alarm and looking inside it. Switch them on in
/// Settings > Developer.
struct DeveloperView: View {
    @State private var alarmService = AlarmService.shared
    @State private var coordinator = WakeCoordinator.shared
    @State private var testCount = 3
    @State private var testIntervalMinutes = 1
    @State private var morningTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? .now

    var body: some View {
        Form {
            Section {
                Stepper("Alarms in chain: \(testCount)", value: $testCount, in: 1...10)
                Stepper("Every \(testIntervalMinutes) min", value: $testIntervalMinutes, in: 1...5)
                Button("Ring in 1 minute") {
                    Task {
                        await alarmService.scheduleTestChain(
                            startingAt: .now.addingTimeInterval(60),
                            count: testCount,
                            interval: Double(testIntervalMinutes) * 60
                        )
                    }
                }
            } header: {
                Text("Quick test")
            } footer: {
                Text("Lock the phone and wait. When it rings, tap \"Prove I'm up\". The app should open and the next alarm in the chain should still ring.")
            }

            Section {
                DatePicker("Ring at", selection: $morningTime, displayedComponents: .hourAndMinute)
                Button("Ring once at that time") {
                    Task {
                        await alarmService.scheduleTestChain(
                            startingAt: AlarmService.nextOccurrence(of: morningTime),
                            count: testCount,
                            interval: Double(testIntervalMinutes) * 60
                        )
                    }
                }
            } header: {
                Text("One-off alarm")
            } footer: {
                Text("A test chain doesn't repeat and has no follow-up check.")
            }

            Section("This morning") {
                LabeledContent("State", value: coordinator.state.phase.rawValue)
                if let outcome = coordinator.state.lastOutcome {
                    LabeledContent("Last outcome", value: outcome.rawValue)
                }
                LabeledContent("Failed tries", value: "\(coordinator.state.attempts)")
                Button("Reset morning state", role: .destructive) {
                    coordinator.resetState()
                }
            }

            Section {
                if alarmService.alarms.isEmpty {
                    Text("No alarms scheduled").foregroundStyle(.secondary)
                } else {
                    ForEach(sortedAlarms) { alarm in
                        HStack {
                            if let date = AlarmService.fireDate(of: alarm) {
                                Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
                            } else {
                                Text("Repeating alarm")
                            }
                            Spacer()
                            Text(label(for: alarm.state))
                                .font(.caption.bold())
                                .foregroundStyle(alarm.state == .alerting ? .orange : .secondary)
                        }
                    }
                    Button("Cancel all alarms", role: .destructive) {
                        alarmService.cancelEverything()
                    }
                }
            } header: {
                Text("Scheduled in AlarmKit (\(alarmService.alarms.count))")
            } footer: {
                if let limit = alarmService.learnedSlotLimit {
                    Text("iOS stopped accepting alarms at \(limit).")
                } else {
                    Text("iOS hasn't refused any alarms yet, so the limit is unknown.")
                }
            }

            Section {
                Button("Schedule again now") {
                    Task { await alarmService.reconcile(prompt: true) }
                }
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sortedAlarms: [Alarm] {
        alarmService.alarms.sorted {
            (AlarmService.fireDate(of: $0) ?? .distantFuture) < (AlarmService.fireDate(of: $1) ?? .distantFuture)
        }
    }

    private func label(for state: Alarm.State) -> String {
        switch state {
        case .scheduled: "Scheduled"
        case .countdown: "Countdown"
        case .paused: "Paused"
        case .alerting: "Ringing"
        @unknown default: "Unknown"
        }
    }
}
