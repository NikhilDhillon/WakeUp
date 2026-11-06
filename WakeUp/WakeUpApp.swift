import SwiftData
import SwiftUI
import UIKit

@main
struct WakeUpApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator = WakeCoordinator.shared
    @State private var alarmService = AlarmService.shared

    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .fullScreenCover(isPresented: $coordinator.isShowingProof) {
                    WakeView()
                }
                // The clock or time zone changed (travel, daylight saving):
                // alarms scheduled for the old clock must be redone.
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { await alarmService.reconcile(prompt: false) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    Task { await alarmService.reconcile(prompt: false) }
                }
        }
        .modelContainer(for: [Mission.self, ReferencePhoto.self, WakeAlarm.self, ProofAttempt.self])
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                coordinator.appBecameActive()
            } else if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
        // An alarm starts ringing while the app is open: go to the proof screen.
        .onChange(of: alarmService.isRinging) { _, ringing in
            if ringing {
                coordinator.proofRequested()
            }
        }
    }
}
