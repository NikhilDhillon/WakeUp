import Foundation

/// A random thing you have to do in the proof photo, so a photo taken the
/// night before (or an old one) won't pass.
enum Challenge: String, CaseIterable, Codable {
    case threeFingers
    case twoFingers
    case thumbsUp
    case peaceSign
    case handOnHead
    case pointUp

    /// Shown to you on the wake screen.
    var instruction: String {
        switch self {
        case .threeFingers: "Hold up 3 fingers"
        case .twoFingers: "Hold up 2 fingers"
        case .thumbsUp: "Give a thumbs up"
        case .peaceSign: "Make a peace sign"
        case .handOnHead: "Put one hand on your head"
        case .pointUp: "Point at the ceiling"
        }
    }

    var symbol: String {
        switch self {
        case .threeFingers, .twoFingers: "hand.raised.fingers.spread.fill"
        case .thumbsUp: "hand.thumbsup.fill"
        case .peaceSign: "hand.raised.fill"
        case .handOnHead: "person.fill"
        case .pointUp: "hand.point.up.fill"
        }
    }

    static func random() -> Challenge {
        allCases.randomElement() ?? .thumbsUp
    }
}
