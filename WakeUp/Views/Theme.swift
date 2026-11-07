import SwiftUI

/// Every colour, size and shape the redesigned screens use, in one place.
/// Colours come from named sets in `Assets.xcassets`, each with a dark appearance.
enum Theme {
    // MARK: Colour

    static let ground = Color("Ground")
    static let card = Color("Card")
    static let inkSecondary = Color("InkSecondary")
    /// Cyan for **text**. The fill cyan (`AccentColor`) fails contrast as text.
    static let accentText = Color("AccentText")
    /// Shapes only (dots, bars), never words.
    static let ready = Color("Ready")
    static let warn = Color("Warn")
    /// Dark text on an `AccentColor` fill.
    static let onAccent = Color.black

    /// The wake screen ignores the system appearance on purpose.
    static let wakeBackground = Color(red: 1, green: 1, blue: 1)
    static let wakeInk = Color(red: 0, green: 0, blue: 0)
    /// Grey text on the white wake screen (5.7:1).
    static let wakeSecondary = Color(red: 0.35, green: 0.36, blue: 0.39)

    // MARK: Shape and spacing

    static let screenMargin: CGFloat = 16
    static let cardRadius: CGFloat = 28
    static let cardPadding: CGFloat = 18
    static let rowRadius: CGFloat = 20
    static let chipRadius: CGFloat = 14
    static let minTapHeight: CGFloat = 44

    // MARK: Type sizes (scaled with `@ScaledMetric`)

    static let cardTimeSize: CGFloat = 70
    static let rowTimeSize: CGFloat = 30
    static let wakeChallengeSize: CGFloat = 72
    /// "AM" is this fraction of the time's size.
    static let meridiemScale: CGFloat = 0.3
}

extension View {
    /// The soft shadow under the Next Up card.
    func cardShadow() -> some View {
        shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
    }
}

/// A rounded, filled box used for the Next Up card and the other alarms.
struct CardBackground: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content.background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func cardBackground(radius: CGFloat = Theme.rowRadius) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

/// A time like "6:45 AM" with the "AM" small and grey.
struct TimeText: View {
    let date: Date
    let size: CGFloat
    var dimmed = false

    @ScaledMetric private var scaled: CGFloat

    init(date: Date, size: CGFloat, dimmed: Bool = false) {
        self.date = date
        self.size = size
        self.dimmed = dimmed
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        let parts = Self.parts(of: date)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.time)
                .font(.system(size: scaled, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let meridiem = parts.meridiem {
                Text(meridiem)
                    .font(.system(size: scaled * Theme.meridiemScale, weight: .regular))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .foregroundStyle(dimmed ? Theme.inkSecondary : Color.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(date.formatted(.dateTime.hour().minute()))
    }

    /// Splits "6:45 AM" into "6:45" and "AM". 24-hour clocks have no meridiem.
    static func parts(of date: Date, locale: Locale = .current) -> (time: String, meridiem: String?) {
        let full = date.formatted(.dateTime.hour().minute().locale(locale))
        let marker = date.formatted(.dateTime.hour().locale(locale))
        // Anything non-numeric in the hour-only format is the AM/PM marker.
        let letters = marker.filter { !$0.isNumber && !$0.isWhitespace }
        guard !letters.isEmpty else { return (full, nil) }
        let time = full
            .replacingOccurrences(of: String(letters), with: "")
            .trimmingCharacters(in: .whitespaces)
        return (time, String(letters))
    }
}
