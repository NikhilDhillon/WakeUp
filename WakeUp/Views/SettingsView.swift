import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.modelKey) private var model = AppSettings.defaultModel
    @AppStorage(AppSettings.strictnessKey) private var strictness = Strictness.normal.rawValue
    @AppStorage(AppSettings.checkMethodKey) private var checkMethod = CheckMethod.decisions.rawValue

    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @AppStorage(AppSettings.offlineBackupKey) private var offlineBackup = true
    @AppStorage(AppSettings.keepThumbnailsKey) private var keepThumbnails = false

    @State private var hasKey = AppSettings.hasAPIKey
    @State private var keyDraft = ""
    @State private var keyError: String?

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Picker("Check with", selection: $checkMethod) {
                        ForEach(CheckMethod.allCases) { method in
                            Text(method.title).tag(method.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    if checkMethod == CheckMethod.responses.rawValue {
                        TextField(AppSettings.defaultModel, text: $model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    }
                } header: {
                    Text("AI check")
                } footer: {
                    if checkMethod == CheckMethod.responses.rawValue {
                        Text("The Responses API also writes a short reason, but is slower and costs more. Any OpenAI model that takes images works; \(AppSettings.defaultModel) is the cheapest.")
                    } else {
                        Text("The Decisions API returns how likely each check is, using \(DecisionsVerifier.model). It's the cheapest and fastest option, but doesn't write a reason.")
                    }
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
                    Text("How sure the AI must be about every check (right place, you in the photo, challenge done, awake, not a screen): lenient 50%, normal 70%, strict 85%.")
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
}

#Preview {
    SettingsView()
}
