import SwiftData
import SwiftUI

@main
struct WakeUpApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator = WakeCoordinator.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .fullScreenCover(isPresented: $coordinator.isShowingProof) {
                    WakeView()
                }
        }
        .modelContainer(for: [Mission.self, ReferencePhoto.self])
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AlarmService.shared.refresh()
                coordinator.appBecameActive()
            }
        }
    }
}
