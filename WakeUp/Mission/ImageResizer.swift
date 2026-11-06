import UIKit

/// Shrinks photos before they're stored. Smaller images keep the database
/// light and, in phase 3, make each AI check cheaper and faster.
enum ImageResizer {
    static let maxDimension: CGFloat = 1024
    static let quality: CGFloat = 0.8

    /// Accepts any format UIImage can read (HEIC, JPEG, PNG …).
    static func jpegData(from data: Data, maxDimension: CGFloat = maxDimension) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpegData(from: image, maxDimension: maxDimension)
    }

    static func jpegData(from image: UIImage, maxDimension: CGFloat = maxDimension) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        // Drawing also bakes in the photo's rotation, so the AI sees it upright.
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
