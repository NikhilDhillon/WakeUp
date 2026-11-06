#if DEBUG
import SwiftData
import UIKit

/// Debug builds only: launch with `-WakeUpSampleData` to fill an empty app
/// with two places, three alarms and a week of history, so every Home state
/// can be checked in the simulator without typing it all in.
enum DebugSeed {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-WakeUpSampleData")
    }

    @MainActor
    static func run(in context: ModelContext) {
        guard isRequested,
              (try? context.fetchCount(FetchDescriptor<WakeAlarm>())) == 0
        else { return }

        let washroom = place("Washroom", "Me sitting in the washroom with the light on", colors: [.systemTeal, .systemBlue, .systemIndigo])
        let kitchen = place("Kitchen", "Standing at the kitchen counter", colors: [.systemOrange, .systemYellow, .systemBrown])
        context.insert(washroom)
        context.insert(kitchen)
        UserDefaults.standard.set(washroom.id.uuidString, forKey: ActiveMission.key)
        UserDefaults.standard.set(true, forKey: AppSettings.setupCompletedKey)

        let weekday = WakeAlarm(hour: 6, minute: 45, weekdays: .weekdays)
        weekday.createdAt = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let weekend = WakeAlarm(hour: 9, minute: 30, weekdays: [1, 7])
        weekend.missionID = kitchen.id.uuidString
        weekend.createdAt = weekday.createdAt
        let off = WakeAlarm(hour: 5, minute: 30, weekdays: [2, 4, 6])
        off.isEnabled = false
        off.chainLength = 7
        off.chainIntervalMinutes = 4
        [weekday, weekend, off].forEach(context.insert)

        // Passed mornings on most of the last few days.
        let verdict = Verdict(probabilities: [.samePlace: 0.95], reason: nil)
        for back in [1, 2, 3, 5, 6] {
            guard let day = Calendar.current.date(byAdding: .day, value: -back, to: .now),
                  let time = Calendar.current.date(bySettingHour: 6, minute: 50, second: 0, of: day)
            else { continue }
            context.insert(ProofAttempt(
                date: time, kind: .wake, missionName: "Washroom", challenge: "Hold up 3 fingers",
                verdict: verdict, passed: true, duration: 2, thumbnail: nil
            ))
        }
        try? context.save()
    }

    private static func place(_ name: String, _ description: String, colors: [UIColor]) -> Mission {
        let mission = Mission(name: name, proofDescription: description)
        for (index, color) in colors.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { ctx in
                color.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            }
            mission.photos.append(ReferencePhoto(jpegData: image.jpegData(compressionQuality: 0.8) ?? Data(), order: index))
        }
        return mission
    }
}
#endif
