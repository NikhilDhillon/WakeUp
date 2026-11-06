import SwiftUI

/// One pill under the "Alarms" title: "Ready for tomorrow", or the worst
/// problem with a button that fixes it. More than one problem shows a "+N"
/// badge, and tapping the pill lists them all.
struct StatusPill: View {
    let status: HomeStatus
    var onAction: (StatusAction) -> Void
    var onShowAll: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let problem = status.worst {
            problemPill(problem)
        } else {
            readyPill
        }
    }

    private var readyPill: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.ready).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(status.readyText)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minTapHeight)
        .background(Theme.card, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func problemPill(_ problem: StatusProblem) -> some View {
        HStack(spacing: 10) {
            Button(action: onShowAll) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warn)
                        .accessibilityHidden(true)
                    Text(problem.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                    if status.extraCount > 0 {
                        Text("+\(status.extraCount)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.warn.opacity(0.18), in: Capsule())
                            .foregroundStyle(Theme.warn)
                            .accessibilityLabel("\(status.extraCount) more")
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(status.extraCount > 0 ? "Shows all problems" : "Shows what's wrong")

            if let action = problem.action, action != .showDetails {
                Button(action.title) { onAction(action) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .foregroundStyle(Theme.onAccent)
                    .frame(minHeight: Theme.minTapHeight)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: Theme.minTapHeight)
        .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.warn.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Every current problem with its full message, opened from the pill.
struct StatusDetailsSheet: View {
    let status: HomeStatus
    var onAction: (StatusAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(status.problems) { problem in
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(problem.title).font(.headline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                    }
                    Text(problem.detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                    if let action = problem.action, action != .showDetails {
                        Button(action.title) {
                            dismiss()
                            onAction(action)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Heads up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension StatusPill {
    /// For previews: build the pill straight from a list of warnings.
    init(
        previewWarnings: [HealthWarning], lastError: String? = nil, notDetermined: Bool = false,
        hasEnabledAlarm: Bool = true
    ) {
        self.init(
            status: HomeStatus.make(
                warnings: previewWarnings, lastError: lastError, authorizationNotDetermined: notDetermined,
                hasAlarms: true, hasEnabledAlarm: hasEnabledAlarm,
                nextRing: Calendar.current.date(byAdding: .hour, value: 10, to: .now), now: .now
            )!,
            onAction: { _ in }, onShowAll: {}
        )
    }
}

#Preview("Pill: every state") {
    ScrollView {
        VStack(spacing: 10) {
            StatusPill(previewWarnings: [])
            StatusPill(previewWarnings: [], lastError: "iOS only allows 64 alarms at once.")
            StatusPill(previewWarnings: [.alarmsBlocked])
            StatusPill(previewWarnings: [.cameraDenied])
            StatusPill(previewWarnings: [.noProof])
            StatusPill(previewWarnings: [.cannotCheckPhoto])
            StatusPill(previewWarnings: [.lowBattery])
            StatusPill(previewWarnings: [.buildExpiring(daysLeft: 2)])
            StatusPill(previewWarnings: [.lowPowerMode])
            StatusPill(previewWarnings: [], notDetermined: true)
            StatusPill(previewWarnings: [], hasEnabledAlarm: false)
            StatusPill(previewWarnings: [.noProof, .lowPowerMode, .lowBattery])
        }
        .padding()
    }
    .background(Theme.ground)
}

#Preview("Pill: dark") {
    VStack(spacing: 10) {
        StatusPill(previewWarnings: [])
        StatusPill(previewWarnings: [.noProof, .lowPowerMode])
    }
    .padding()
    .background(Theme.ground)
    .preferredColorScheme(.dark)
}

#Preview("Pill: AX5") {
    ScrollView {
        VStack(spacing: 10) {
            StatusPill(previewWarnings: [])
            StatusPill(previewWarnings: [.cannotCheckPhoto, .lowPowerMode])
        }
        .padding()
    }
    .background(Theme.ground)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Details sheet") {
    StatusDetailsSheet(
        status: HomeStatus.make(
            warnings: [.noProof, .lowPowerMode, .lowBattery], lastError: nil, authorizationNotDetermined: false,
            hasAlarms: true, hasEnabledAlarm: true, nextRing: nil, now: .now
        )!,
        onAction: { _ in }
    )
}
