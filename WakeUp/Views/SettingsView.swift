import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.modelKey) private var model = AppSettings.defaultModel
    @AppStorage(AppSettings.strictnessKey) private var strictness = Strictness.normal.rawValue

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
                    TextField(AppSettings.defaultModel, text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Model")
                } footer: {
                    Text("Any OpenAI model that accepts images. Leave it as \(AppSettings.defaultModel) unless the checks are too slow or too inaccurate.")
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
                    Text("Every check must pass either way. Strictness sets how sure the AI must be overall: lenient 50%, normal 70%, strict 85%.")
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
