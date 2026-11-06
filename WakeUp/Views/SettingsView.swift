import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.modelKey) private var model = AppSettings.defaultModel
    @AppStorage(AppSettings.strictnessKey) private var strictness = Strictness.normal.rawValue
    @AppStorage(AppSettings.checkMethodKey) private var checkMethod = CheckMethod.decisions.rawValue
    @AppStorage(AppSettings.serviceURLKey) private var serviceURL = ""
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @AppStorage(AppSettings.offlineBackupKey) private var offlineBackup = true
    @AppStorage(AppSettings.keepThumbnailsKey) private var keepThumbnails = false

    /// Called after Settings closes when the user asks to run setup again.
    var onRunSetup: () -> Void = {}

    @State private var hasKey = AppSettings.hasAPIKey
    @State private var keyDraft = ""
    @State private var keyError: String?

    private var usesKey: Bool {
        checkMethod == CheckMethod.decisions.rawValue || checkMethod == CheckMethod.responses.rawValue
    }

    var body: some View {
        NavigationStack {
            Form {
                aiCheckSection

                if usesKey {
                    keySection
                }
                if checkMethod == CheckMethod.service.rawValue {
                    serviceSection
                }

                Section {
                    Picker("Strictness", selection: $strictness) {
                        ForEach(Strictness.allCases) { level in
                            Text(level.title).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How strict the check is")
                } footer: {
                    Text("How sure the AI must be about every check (right place, you in the photo, challenge done, awake, not a screen): lenient 50%, normal 70%, strict 85%. The place check is held a little higher and the awake check a little lower.")
                }

                Section {
                    Toggle("Check on this phone if offline", isOn: $offlineBackup)
                } header: {
                    Text("No internet")
                } footer: {
                    Text("If OpenAI can't be reached (after one retry), WakeUp checks for your face and the right place on the phone instead. It's a weaker check, so a follow-up check always comes later that morning.")
                }

                Section {
                    Toggle("Keep a small thumbnail of wake photos", isOn: $keepThumbnails)
                } header: {
                    Text("History")
                } footer: {
                    Text("Off by default. Photos are never kept; this saves a tiny 200 px copy on this phone to show in History.")
                }

                Section {
                    Button("Run setup again") {
                        dismiss()
                        onRunSetup()
                    }
                    Label("Photos you take are sent to OpenAI to be checked (unless you pick the on-phone check) and aren't kept by WakeUp.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Setup and privacy")
                }

                Section {
                    Toggle("Developer tools", isOn: $developerMode)
                    if developerMode {
                        NavigationLink("Open developer tools") { DeveloperView() }
                    }
                } footer: {
                    Text("Test alarms and a look at what's scheduled.")
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

    // MARK: Sections

    private var aiCheckSection: some View {
        Section {
            Picker("Check with", selection: $checkMethod) {
                ForEach(CheckMethod.allCases) { method in
                    Text(method.title).tag(method.rawValue)
                }
            }
            .pickerStyle(.menu)
            if checkMethod == CheckMethod.responses.rawValue {
                TextField(AppSettings.defaultModel, text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            }
        } header: {
            Text("AI check")
        } footer: {
            switch CheckMethod(rawValue: checkMethod) ?? .decisions {
            case .decisions:
                Text("The Decisions API returns how likely each check is, using \(DecisionsVerifier.model). It's the cheapest and fastest option, but doesn't write a reason.")
            case .responses:
                Text("The Responses API also writes a short reason, but is slower and costs more. Any OpenAI model that takes images works; \(AppSettings.defaultModel) is the cheapest.")
            case .service:
                Text("Uses a WakeUp service instead of your own OpenAI key.")
            case .onPhone:
                Text("Nothing leaves your phone, but only a face and the right place are checked. A follow-up check always comes later that morning.")
            }
        }
    }

    private var keySection: some View {
        Section {
            if hasKey {
                Label("Key saved on this iPhone", systemImage: "key.fill")
                    .foregroundStyle(.green)
                Button("Remove key", role: .destructive) {
                    AppSettings.removeAPIKey()
                    hasKey = false
                }
            } else {
                SecureField("sk-…", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Save key") {
                    if AppSettings.setAPIKey(keyDraft) {
                        keyDraft = ""
                        keyError = nil
                        hasKey = true
                    } else {
                        keyError = "Couldn't save the key. Check it isn't empty and try again."
                    }
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if let keyError {
                    Text(keyError).font(.footnote).foregroundStyle(.red)
                }
            }
        } header: {
            Text("OpenAI API key")
        } footer: {
            Text("Stored in the iPhone Keychain and only sent to OpenAI. Create one at platform.openai.com under API keys.")
        }
    }

    private var serviceSection: some View {
        Section {
            TextField("https://wakeup-proxy.example.workers.dev", text: $serviceURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.body.monospaced())
            if !serviceURL.isEmpty, AppSettings.serviceURL == nil {
                Text("The address must start with https://")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("WakeUp service address")
        } footer: {
            Text("A proxy that holds the OpenAI key for you (see proxy/ in the repo). Your photos go to it and then to OpenAI. This phone is counted by a random ID, not by name.")
        }
    }
}

#Preview {
    SettingsView()
}
