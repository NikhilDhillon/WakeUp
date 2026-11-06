import AlarmKit
import Foundation

/// Extra data attached to every alarm in a wake chain.
struct WakeAlarmMetadata: AlarmMetadata {
    /// All alarms scheduled together for one morning share a chain ID.
    var chainID: UUID
    /// Position in the chain (0 = first ring).
    var index: Int
}
