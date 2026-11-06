import AlarmKit
import SwiftData
import SwiftUI

/// Home: your proof, the alarm test tools, and the morning alarm.
struct HomeView: View {
    @State private var alarmService = AlarmService.shared
    @State private var coordinator = WakeCoordinator.shared
    @Query(sort: \Mission.createdAt) private var missions: [Mission]
    @AppStorage(ActiveMission.key) private var activeMissionID = ""
    @State private var showingSettings = false
    @State private var hasAPIKey = AppSettings.hasAPIKey
    @State private var testCount = 3
    @State private var testIntervalMinutes = 1
    @State private var morningTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? .now
    @State private var morningCount = 10
    @State private var morningIntervalMinutes = 3

    var body: some View {
        NavigationStack {
            Form {
                permissionSection
                proofSection
                if let lastPassed = coordinator.lastPassed {
                    Section("Last proof") {
                        Label {
                            Text(lastPassed, format: .dateTime.weekday(.wide).hour().minute())
                        } icon: {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                    }
                }
                testSection
                morningSection
                scheduledSection
                if let error = alarmService.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("WakeUp")
            .refreshable { alarmService.refresh() }
            .toolbar {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                hasAPIKey = AppSettings.hasAPIKey
            }) {
                SettingsView()
            }
        }
    }

    // MARK: Sections

    private var permissionSection: some View {
        Section("Permission") {
            switch alarmService.authorization {
            case .authorized:
                Label("Alarms allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Alarms blocked. Turn them on in Settings > WakeUp.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            case .notDetermined:
                Button("Allow alarms") {
                    Task { await alarmService.requestAuthorization() }
                }
            @unknown default:
                Text("Unknown permission state")
            }
        }
    }

    private var activeMission: Mission? {
        ActiveMission.resolve(id: activeMissionID, in: missions)
    }

    private var proofSection: some View {
        Section {
            NavigationLink {
                MissionsView()
            } label: {
                if let mission = activeMission {
                    HStack(spacing: 12) {
                        MissionThumbnail(mission: mission, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mission.name).font(.headline)
                            Text(mission.proofDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Label("Set up your proof", systemImage: "camera.viewfinder")
                }
            }
            if !hasAPIKey {
                Button {
                    showingSettings = true
                } label: {
                    Label("Add your OpenAI key to turn on the AI check", systemImage: "key")
                }
            }
        } header: {
            Text("Proof")
        } footer: {
            if activeMission == nil {
                Text("Describe what proves you're up and add a few photos of the place.")
            }
        }
    }

    private var testSection: some View {
        Section {
            Stepper("Alarms in chain: \(testCount)", value: $testCount, in: 1...10)
            Stepper("Every \(testIntervalMinutes) min", value: $testIntervalMinutes, in: 1...5)
            Button("Ring in 1 minute") {
                Task {
                    await alarmService.scheduleChain(
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
    }

    private var morningSection: some View {
        Section {
            DatePicker("Wake at", selection: $morningTime, displayedComponents: .hourAndMinute)
            Stepper("Re-ring \(morningCount) times", value: $morningCount, in: 1...20)
            Stepper("Every \(morningIntervalMinutes) min", value: $morningIntervalMinutes, in: 1...10)
            Button("Set morning alarm") {
                Task {
                    await alarmService.scheduleChain(
                        startingAt: AlarmService.nextOccurrence(of: morningTime),
                        count: morningCount,
                        interval: Double(morningIntervalMinutes) * 60
                    )
                }
            }
        } header: {
            Text("Morning alarm")
        } footer: {
            if activeMission == nil {
                Text("Set up your proof first, or the alarm can only be stopped without proof.")
            } else {
                Text("Schedules one chain for the next time the clock shows this time.")
            }
        }
    }

    private var scheduledSection: some View {
        Section("Scheduled") {
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
        }
    }

    // MARK: Helpers

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

#Preview {
    HomeView()
        .modelContainer(for: [Mission.self, ReferencePhoto.self], inMemory: true)
}
