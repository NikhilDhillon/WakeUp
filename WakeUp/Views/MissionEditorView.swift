import PhotosUI
import SwiftData
import SwiftUI

/// Create or edit a mission. Changes are kept in local state and only
/// written to the database on Save, so Cancel throws them away.
struct MissionEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ActiveMission.key) private var activeMissionID = ""

    private let mission: Mission?

    @State private var name: String
    @State private var details: String
    @State private var photos: [DraftPhoto]
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var photoError: String?
    @FocusState private var isTyping: Bool
    @State private var practicing = false
    @State private var takingPhotos = false
    /// Picked once per practice run, so redraws don't swap the challenge.
    @State private var practiceChallenge = Challenge.random()

    init(mission: Mission?) {
        self.mission = mission
        _name = State(initialValue: mission?.name ?? "")
        _details = State(initialValue: mission?.proofDescription ?? "")
        _photos = State(initialValue: mission?.orderedPhotos.compactMap(DraftPhoto.init) ?? [])
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("e.g. Washroom", text: $name)
                    .textInputAutocapitalization(.words)
                    .focused($isTyping)
            }

            Section {
                TextEditor(text: $details)
                    .frame(minHeight: 110)
                    .focused($isTyping)
                    .overlay(alignment: .topLeading) {
                        if details.isEmpty {
                            Text("Me sitting in the washroom with the light on and the sink behind me")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("What proves you're up?")
            } footer: {
                Text("Describe what your morning photo should show. The AI checks the photo against this and the reference photos.")
            }

            photosSection

            if !canSave {
                Section {
                    Label(missingText, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let mission, mission.isReady {
                Section {
                    Button {
                        practiceChallenge = .random()
                        practicing = true
                    } label: {
                        Label("Practice with this proof", systemImage: "camera.viewfinder")
                    }
                    .disabled(!Verifiers.isConfigured)
                } footer: {
                    Text(Verifiers.isConfigured
                        ? "Take a photo now and see what the AI says. Doesn't touch your alarms. Uses the saved version of this proof."
                        : "Set up how photos are checked in Settings to practice.")
                }
            }
        }
        .fullScreenCover(isPresented: $practicing) {
            if let mission {
                ProofCaptureView(mission: mission, challenge: practiceChallenge, mode: .practice)
            }
        }
        .fullScreenCover(isPresented: $takingPhotos) {
            ReferenceCameraView(remaining: Mission.maxPhotos - photos.count) { data in
                if photos.count < Mission.maxPhotos,
                   let jpeg = ImageResizer.jpegData(from: data),
                   let draft = DraftPhoto(jpegData: jpeg) {
                    photos.append(draft)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(mission == nil ? "New proof" : "Edit proof")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isTyping = false }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPicked(items) }
        }
    }

    // MARK: Photos

    private var photosSection: some View {
        Section {
            if !photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(photos) { photo in
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    photos.removeAll { $0.id == photo.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .padding(4)
                                .accessibilityLabel("Remove photo")
                            }
                    }
                }
                .padding(.vertical, 4)
            }

            if photos.count < Mission.maxPhotos {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: Mission.maxPhotos - photos.count,
                    matching: .images
                ) {
                    if isLoadingPhotos {
                        HStack {
                            ProgressView()
                            Text("Adding photos…")
                        }
                    } else {
                        Label("Add photos", systemImage: "photo.on.rectangle.angled")
                    }
                }
                .disabled(isLoadingPhotos)
                #if !targetEnvironment(simulator)
                Button {
                    takingPhotos = true
                } label: {
                    Label("Take photos now", systemImage: "camera")
                }
                #endif
            }

            if let photoError {
                Text(photoError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Reference photos (\(photos.count) of \(Mission.maxPhotos))")
        } footer: {
            Text("Add \(Mission.minPhotos) to \(Mission.maxPhotos) photos of the place from different angles. You don't need to be in them.")
        }
    }

    private func addPicked(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        photoError = nil
        var failed = 0
        for item in items where photos.count < Mission.maxPhotos {
            if let data = try? await item.loadTransferable(type: Data.self),
               let jpeg = ImageResizer.jpegData(from: data),
               let draft = DraftPhoto(jpegData: jpeg) {
                photos.append(draft)
            } else {
                failed += 1
            }
        }
        if failed > 0 {
            photoError = failed == 1 ? "1 photo couldn't be added." : "\(failed) photos couldn't be added."
        }
        pickerItems = []
        isLoadingPhotos = false
    }

    // MARK: Saving

    private var canSave: Bool {
        Mission.isReady(name: name, description: details, photoCount: photos.count)
    }

    private var missingText: String {
        var missing: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("a name")
        }
        if details.trimmingCharacters(in: .whitespacesAndNewlines).count < Mission.minDescriptionLength {
            missing.append("a description")
        }
        if photos.count < Mission.minPhotos {
            let needed = Mission.minPhotos - photos.count
            missing.append(needed == 1 ? "1 more photo" : "\(needed) more photos")
        }
        return "To save, add " + ListFormatter.localizedString(byJoining: missing) + "."
    }

    private func save() {
        let target: Mission
        if let mission {
            target = mission
        } else {
            target = Mission(name: "", proofDescription: "")
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.proofDescription = details.trimmingCharacters(in: .whitespacesAndNewlines)

        // Replace the photos wholesale; there are at most five.
        let old = target.photos
        target.photos = []
        old.forEach(context.delete)
        for (index, draft) in photos.enumerated() {
            let photo = ReferencePhoto(jpegData: draft.jpegData, order: index)
            context.insert(photo)
            photo.mission = target
        }

        try? context.save()
        if activeMissionID.isEmpty {
            activeMissionID = target.id.uuidString
        }
        dismiss()
    }
}

/// A photo in the editor that hasn't been saved yet.
struct DraftPhoto: Identifiable {
    let id = UUID()
    let jpegData: Data
    let image: UIImage

    init?(jpegData: Data) {
        guard let image = UIImage(data: jpegData) else { return nil }
        self.jpegData = jpegData
        self.image = image
    }

    init?(_ photo: ReferencePhoto) {
        self.init(jpegData: photo.jpegData)
    }
}

#Preview {
    NavigationStack {
        MissionEditorView(mission: nil)
    }
    .modelContainer(for: [Mission.self, ReferencePhoto.self], inMemory: true)
}
