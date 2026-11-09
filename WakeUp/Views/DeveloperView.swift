import AlarmKit
import SwiftData
import SwiftUI

/// How photos are checked, plus tools for trying the alarm and looking
/// inside it. Switch them on in Settings > Developer tools.
struct DeveloperView: View {
    @State private var alarmService = AlarmService.shared
    @State private var coordinator = WakeCoordinator.shared
    @State private var testCount = 3
    @State private var testIntervalMinutes = 1
    @Query(sort: \Mission.createdAt) private var missions: [Mission]
    @AppStorage(ActiveMission.key) private var activeMissionID = ""
    @State private var quickNapMessage: String?
    @State private var morningTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? .now

    var body: some View {
        Form {
            // How photos are checked: method, OpenAI key, offline backup.
            PhotoCheckSettings()

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
                Button("Quick nap") {
                    Task { await startQuickNap() }
                }
                .disabled(alarmService.nap != nil)
                if let quickNapMessage {
                    Text(quickNapMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Nap")
            } footer: {
                Text("Rings in 1 minute with 3 rings 1 minute apart and 2 snoozes of 1 minute, using your default proof. Lock the phone, press Stop to snooze, and check each step of the nap plan.")
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

    private func startQuickNap() async {
        let mission = ActiveMission.resolve(id: activeMissionID, in: missions)
        let nap = NapSession.make(
            now: .now, minutes: 1, missionID: mission?.id.uuidString, proofName: mission?.name ?? "",
            chainLength: 3, chainIntervalMinutes: 1, followUpMinutes: 0, snoozes: 2, snoozeMinutes: 1, allowShort: true
        )
        switch await alarmService.startNap(nap) {
        case .started: quickNapMessage = "Nap started: rings at \(nap.ringsAt.formatted(date: .omitted, time: .shortened))."
        case .tooManyAlarms(let fit): quickNapMessage = "iOS only has room for \(fit) alarms right now."
        case .failed(let reason): quickNapMessage = reason
        }
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
