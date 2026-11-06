import SwiftData
import SwiftUI

/// Your saved proofs. The one with the filled circle is what the alarm uses.
struct MissionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Mission.createdAt) private var missions: [Mission]
    @AppStorage(ActiveMission.key) private var activeMissionID = ""

    @Query private var alarms: [WakeAlarm]
    @State private var editing: EditorTarget?
    @State private var pendingDelete: [Mission] = []

    var body: some View {
        List {
            if missions.isEmpty {
                ContentUnavailableView {
                    Label("No proof yet", systemImage: "camera.viewfinder")
                } description: {
                    Text("Describe what proves you're up, like sitting in your washroom, and add a few photos of the place.")
                } actions: {
                    Button("Add your first proof") { editing = .new }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(missions) { mission in
                        row(for: mission)
                    }
                    .onDelete { offsets in pendingDelete = offsets.map { missions[$0] } }
                } footer: {
                    Text("Tap the circle to choose which proof the alarm asks for.")
                }
            }
        }
        .navigationTitle("Proofs")
        .toolbar {
            if !missions.isEmpty {
                Button {
                    editing = .new
                } label: {
                    Label("Add proof", systemImage: "plus")
                }
            }
        }
        .confirmationDialog(
            deleteTitle, isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                delete(pendingDelete)
                pendingDelete = []
            }
        } message: {
            Text(deleteMessage)
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                switch target {
                case .new:
                    MissionEditorView(mission: nil)
                case .existing(let mission):
                    MissionEditorView(mission: mission)
                }
            }
        }
    }

    private func row(for mission: Mission) -> some View {
        HStack(spacing: 12) {
            Button {
                activeMissionID = mission.id.uuidString
            } label: {
                Image(systemName: isActive(mission) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isActive(mission) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive(mission) ? "Used by the alarm" : "Use for the alarm")

            Button {
                editing = .existing(mission)
            } label: {
                HStack(spacing: 12) {
                    MissionThumbnail(mission: mission, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mission.name).font(.headline)
                        Text(mission.proofDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text("\(mission.photos.count) photos")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func isActive(_ mission: Mission) -> Bool {
        ActiveMission.resolve(id: activeMissionID, in: missions)?.id == mission.id
    }

    private var deleteTitle: String {
        pendingDelete.count == 1 ? "Delete \"\(pendingDelete[0].name)\"?" : "Delete these proofs?"
    }

    private var deleteMessage: String {
        let ids = Set(pendingDelete.map { $0.id.uuidString })
        let using = alarms.filter { ids.contains($0.missionID) }.count
        return using == 0
            ? "This can't be undone."
            : "\(using) alarm\(using == 1 ? " uses" : "s use") it and will switch to your default proof."
    }

    private func delete(_ removed: [Mission]) {
        let ids = Set(removed.map { $0.id.uuidString })
        // Alarms that pointed at a deleted proof go back to the default.
        for alarm in alarms where ids.contains(alarm.missionID) { alarm.missionID = "" }
        let removedActive = removed.contains { $0.id.uuidString == activeMissionID }
        removed.forEach(context.delete)
        try? context.save()
        if removedActive {
            activeMissionID = missions.first { m in !removed.contains { $0.id == m.id } }?.id.uuidString ?? ""
        }
    }

    enum EditorTarget: Identifiable {
        case new
        case existing(Mission)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let mission): mission.id.uuidString
            }
        }
    }
}

/// The first reference photo of a mission, or a placeholder.
struct MissionThumbnail: View {
    let mission: Mission
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let data = mission.orderedPhotos.first?.jpegData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack {
        MissionsView()
    }
    .modelContainer(for: [Mission.self, ReferencePhoto.self], inMemory: true)
}
