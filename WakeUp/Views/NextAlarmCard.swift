import SwiftUI

/// The big card at the top of Home: the next alarm to ring, its days, its
/// place, and the two chips (skip, difficulty).
struct NextAlarmCard: View {
    @Bindable var alarm: WakeAlarm
    /// The proof this alarm will use, if any.
    var mission: Mission?
    /// The next real ring. nil = the alarm is off.
    var ring: Date?
    var onEdit: () -> Void
    var onOpenPlace: () -> Void
    var onToggleSkip: () -> Void
    /// Called just before the on/off switch changes the alarm.
    var willToggle: () -> Void = {}

    var body: some View {
        // The countdown ticks once a minute.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        let chip = NextUp.skipChip(for: alarm.spec, now: now)
        return VStack(alignment: .leading, spacing: 14) {
            header(now: now)

            Button(action: onEdit) {
                TimeText(date: alarm.timeOfDay, size: Theme.cardTimeSize, dimmed: ring == nil)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            DayDots(weekdays: alarm.weekdays)

            Divider()

            placeRow

            chips(chip)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The shadow belongs to the card's shape, not to the text on it.
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.card)
                .cardShadow()
        }
        .opacity(ring == nil ? 0.7 : 1)
        // One spoken element; the actions replace the separate buttons.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary(now: now))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Edit alarm", onEdit)
        .accessibilityAction(named: alarm.isEnabled ? "Turn off" : "Turn on") {
            willToggle()
            alarm.isEnabled.toggle()
        }
        .accessibilityAction(named: "Open place", onOpenPlace)
        .modifier(SkipActionModifier(chip: chip, perform: onToggleSkip))
    }

    // MARK: Parts

    private func header(now: Date) -> some View {
        HStack {
            Text(headerText(now: now))
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(ring == nil ? Theme.inkSecondary : Theme.accentText)
            Spacer()
            Toggle("Alarm on", isOn: Binding(
                get: { alarm.isEnabled },
                set: { willToggle(); alarm.isEnabled = $0 }
            ))
                .labelsHidden()
                .tint(.accentColor)
        }
    }

    private func headerText(now: Date) -> String {
        guard let ring else { return "OFF" }
        return NextUp.countdownLabel(to: ring, now: now)
    }

    private var placeRow: some View {
        Button(action: onOpenPlace) {
            HStack(spacing: 12) {
                if let mission, mission.isReady {
                    MissionThumbnail(mission: mission, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mission.name).font(.headline).foregroundStyle(Color.primary)
                        Text(mission.proofDescription)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(Theme.inkSecondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("Choose a place")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(minHeight: Theme.minTapHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chips(_ chip: NextUp.SkipChip?) -> some View {
        let difficulty = Button(action: onEdit) {
            chipLabel(
                AlarmDifficulty.chipText(
                    chainLength: alarm.chainLength, intervalMinutes: alarm.chainIntervalMinutes,
                    followUpMinutes: alarm.followUpMinutes
                ),
                systemImage: "bell.badge"
            )
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 6) {
            // Side by side when they fit; stacked on narrow screens and large text.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if let chip { skipButton(chip) }
                    difficulty
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let chip { skipButton(chip) }
                    difficulty
                }
            }
            if let reason = chip?.disabledReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func skipButton(_ chip: NextUp.SkipChip) -> some View {
        Button(action: onToggleSkip) {
            chipLabel(chip.title, systemImage: chip.isUndo ? "arrow.uturn.backward" : "forward.end", prominent: !chip.isUndo)
        }
        .buttonStyle(.plain)
        .disabled(chip.disabledReason != nil)
        .opacity(chip.disabledReason == nil ? 1 : 0.45)
    }

    private func chipLabel(_ title: String, systemImage: String, prominent: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(prominent ? Theme.card : Color.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minTapHeight)
        .background(
            prominent ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Theme.ground),
            in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
        )
        .fixedSize()
    }

    private func spokenSummary(now: Date) -> String {
        let time = alarm.timeOfDay.formatted(.dateTime.hour().minute())
        let days = WakeAlarm.summary(of: alarm.weekdays).lowercased()
        let place = mission.map(\.name) ?? "no place chosen"
        guard let ring else { return "Alarm, \(time), \(days), off, \(place)" }
        return "Next alarm, \(time), \(days), \(NextUp.spokenCountdown(to: ring, now: now)), \(place)"
    }
}

/// Adds the Skip / Undo skip VoiceOver action only when there is one.
private struct SkipActionModifier: ViewModifier {
    let chip: NextUp.SkipChip?
    let perform: () -> Void

    func body(content: Content) -> some View {
        if let chip, chip.disabledReason == nil {
            content.accessibilityAction(named: chip.title, perform)
        } else {
            content
        }
    }
}

// MARK: Previews

@MainActor
private enum CardSamples {
    static func alarm(
        hour: Int = 6, minute: Int = 45, weekdays: Set<Int> = .weekdays, enabled: Bool = true,
        length: Int = 10, interval: Int = 3, followUp: Int = 12, skipTomorrow: Bool = false
    ) -> WakeAlarm {
        let alarm = WakeAlarm(hour: hour, minute: minute, weekdays: weekdays)
        alarm.isEnabled = enabled
        alarm.chainLength = length
        alarm.chainIntervalMinutes = interval
        alarm.followUpMinutes = followUp
        if skipTomorrow, let next = SchedulePlanner.skippableOccurrence(of: alarm.spec, after: .now) {
            alarm.skippedDays = [next.day]
        }
        return alarm
    }

    static var mission: Mission {
        let mission = Mission(name: "Washroom", proofDescription: "Me sitting in the washroom with the light on")
        for index in 0..<3 { mission.photos.append(ReferencePhoto(jpegData: Data(), order: index)) }
        return mission
    }

    static func ring(for alarm: WakeAlarm) -> Date? {
        SchedulePlanner.nextRing(of: alarm.spec, after: .now)
    }

    static func card(_ alarm: WakeAlarm, mission: Mission? = nil, withPlace: Bool = true) -> some View {
        NextAlarmCard(
            alarm: alarm, mission: withPlace ? (mission ?? Self.mission) : nil, ring: ring(for: alarm),
            onEdit: {}, onOpenPlace: {}, onToggleSkip: {}
        )
        .padding()
        .background(Theme.ground)
    }
}

#Preview("Card: normal") { CardSamples.card(CardSamples.alarm()) }
#Preview("Card: dark") { CardSamples.card(CardSamples.alarm()).preferredColorScheme(.dark) }
#Preview("Card: off") { CardSamples.card(CardSamples.alarm(enabled: false)) }
#Preview("Card: skipped") { CardSamples.card(CardSamples.alarm(weekdays: .everyDay, skipTomorrow: true)) }
#Preview("Card: no place") { CardSamples.card(CardSamples.alarm(), withPlace: false) }
#Preview("Card: custom difficulty") { CardSamples.card(CardSamples.alarm(length: 7, interval: 4, followUp: 15)) }
#Preview("Card: AX5") {
    ScrollView { CardSamples.card(CardSamples.alarm()) }
        .environment(\.dynamicTypeSize, .accessibility5)
}
