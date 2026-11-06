import BackgroundTasks
import Foundation

/// Asks iOS to wake the app now and then (about nightly) so it can top up
/// the next mornings' alarms even if you haven't opened it for a few days.
/// iOS decides when, so this is a safety net: the alarms are also topped up
/// every time you open the app and every time you pass.
enum BackgroundRefresh {
    static let identifier = "com.nikhildhillon.WakeUp.refresh"

    /// Call once while the app launches.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            schedule()
            let work = Task { @MainActor in
                await AlarmService.shared.reconcile(prompt: false)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Asks for the next refresh, around 8 hours from now at the earliest.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 8 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
