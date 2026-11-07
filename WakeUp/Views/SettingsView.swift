import SwiftUI

/// The app's settings: one short row each. The longer explanations live on
/// the Privacy page, and the photo check (key, method, offline backup) in
/// Developer tools.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StrictnessSlider.key) private var strictnessPercent = StrictnessSlider.defaultPercent
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @AppStorage(AppSettings.keepThumbnailsKey) private var keepThumbnails = false
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue

    /// Called after Settings closes when the user asks to run setup again.
    var onRunSetup: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    strictnessRow
                } header: {
                    Text("Wake-up check")
                } footer: {
                    Text("How sure the AI must be before the alarm stops.")
                }

                Section("App") {
                    Picker(selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)

                    Toggle(isOn: $keepThumbnails) {
                        Label("Photo thumbnails in History", systemImage: "photo.on.rectangle")
                    }
                }

                Section {
                    Button {
                        dismiss()
                        onRunSetup()
                    } label: {
                        Label {
                            Text("Run setup again").foregroundStyle(Color.primary)
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy", systemImage: "lock.shield")
                    }
                }

                Section {
                    Toggle(isOn: $developerMode) {
                        Label("Developer tools", systemImage: "hammer")
                    }
                    if developerMode {
                        NavigationLink {
                            DeveloperView()
                        } label: {
                            Label("Photo check and test alarms", systemImage: "wrench.and.screwdriver")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// "Strictness  70% · Normal" over a 50–95% slider.
    private var strictnessRow: some View {
        let percent = StrictnessSlider.clamped(strictnessPercent)
        let name = StrictnessSlider.name(for: percent)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Strictness", systemImage: "checkmark.shield")
                Spacer()
                Text("\(percent)% · \(name)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Theme.accentText)
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(
                    get: { Double(percent) },
                    set: { strictnessPercent = StrictnessSlider.clamped(Int($0.rounded())) }
                ),
                in: Double(StrictnessSlider.range.lowerBound)...Double(StrictnessSlider.range.upperBound),
                step: Double(StrictnessSlider.step)
            ) {
                Text("Strictness")
            } minimumValueLabel: {
                Text("Easier").font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("Stricter").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityValue("\(percent) percent, \(name)")
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: percent)
    }
}

/// What happens to your photos and key, in a few plain lines.
struct PrivacyView: View {
    var body: some View {
        Form {
            Section("Wake-up photos") {
                Text("Each photo is sent with your reference photos to OpenAI (or your WakeUp service) to be checked, then thrown away. WakeUp doesn't keep it.")
                Text("The on-phone check sends nothing anywhere.")
            }
            Section("Thumbnails") {
                Text("Off unless you turn on Photo thumbnails in History. Then a tiny 200 px copy of each wake photo stays on this iPhone.")
            }
            Section("Your OpenAI key") {
                Text("Kept in this iPhone's Keychain, never synced, and only ever sent to OpenAI.")
            }
        }
        .font(.subheadline)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
