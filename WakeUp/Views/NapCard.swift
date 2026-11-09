import SwiftUI

/// Home's card while a nap is set: a big countdown to the ring, the proof
/// it will ask for, and the two buttons. It sits above Next Up.
struct NapCard: View {
    let nap: NapSession
    var onUpEarly: () -> Void
    var onCancel: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 64

    var body: some View {
        // Ticks every second: it's a countdown.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        let stage = nap.stage(at: now)
        return VStack(alignment: .leading, spacing: 14) {
            Text(headline(stage))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            if stage == .ringing {
                Text("Nap's over")
                    .font(.system(size: countdownSize * 0.6, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Text(NapSession.countdownText(from: now, to: nap.ringsAt))
                    .font(.system(size: countdownSize, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("Rings in \(NapSession.spokenCountdown(from: now, to: nap.ringsAt))")
            }

            Text(detail(stage))
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)

            HStack(spacing: 10) {
                Button(action: onUpEarly) {
                    Text(stage == .ringing ? "Prove I'm up" : "I'm up early")
                        .font(.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)

                if nap.canCancel(at: now) {
                    Button(action: onCancel) {
                        Text("Cancel nap")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.card)
                .cardShadow()
        }
    }

    private func headline(_ stage: NapSession.Stage) -> String {
        switch stage {
        case .waiting: "Napping"
        case .snoozed: "Snoozed"
        case .ringing: "Wake up"
        case .done: "Done"
        }
    }

    /// "Rings at 3:42 PM · Desk", or while snoozed
    /// "Snoozed · rings at 3:52 PM · 1 snooze left".
    private func detail(_ stage: NapSession.Stage) -> String {
        let time = nap.ringsAt.formatted(date: .omitted, time: .shortened)
        let place = nap.proofName.isEmpty ? nil : nap.proofName
        switch stage {
        case .waiting:
            return (["Rings at \(time)"] + [place].compactMap { $0 }).joined(separator: " · ")
        case .snoozed:
            return ["Snoozed", "rings at \(time)", nap.snoozesLeftText.lowercasedFirst]
                .joined(separator: " · ")
        case .ringing:
            return ([nap.snoozesLeft > 0 ? nap.snoozesLeftText : "Only a photo stops it"] + [place].compactMap { $0 })
                .joined(separator: " · ")
        case .done:
            return "Passed"
        }
    }
}

private extension String {
    var lowercasedFirst: String {
        prefix(1).lowercased() + dropFirst()
    }
}
