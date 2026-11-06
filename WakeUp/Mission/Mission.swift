import Foundation
import SwiftData

/// What counts as proof that you're up: a written description plus a few
/// reference photos of the place (for example, your washroom).
@Model
final class Mission {
    var id: UUID = UUID()
    var name: String = ""
    /// In your own words, what the morning photo should show.
    var proofDescription: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ReferencePhoto.mission)
    var photos: [ReferencePhoto] = []

    static let minPhotos = 3
    static let maxPhotos = 5
    static let minDescriptionLength = 10

    init(name: String, proofDescription: String) {
        self.name = name
        self.proofDescription = proofDescription
    }

    /// SwiftData doesn't keep array order, so photos carry their own.
    var orderedPhotos: [ReferencePhoto] {
        photos.sorted { $0.order < $1.order }
    }

    /// Enough to run the AI check: a name, a real description, and at
    /// least `minPhotos` reference photos.
    var isReady: Bool {
        Self.isReady(name: name, description: proofDescription, photoCount: photos.count)
    }

    static func isReady(name: String, description: String, photoCount: Int) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && description.trimmingCharacters(in: .whitespacesAndNewlines).count >= minDescriptionLength
            && (minPhotos...maxPhotos).contains(photoCount)
    }
}

/// One reference photo, already shrunk to about 1024 px (see `ImageResizer`).
@Model
final class ReferencePhoto {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var jpegData: Data = Data()
    var order: Int = 0
    var addedAt: Date = Date()
    var mission: Mission?

    init(jpegData: Data, order: Int) {
        self.jpegData = jpegData
        self.order = order
    }
}
