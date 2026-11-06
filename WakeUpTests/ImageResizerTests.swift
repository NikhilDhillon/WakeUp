import Testing
import UIKit
@testable import WakeUp

struct ImageResizerTests {
    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func shrinksLongSideTo1024() throws {
        let data = try #require(ImageResizer.jpegData(from: image(width: 3000, height: 2000)))
        let result = try #require(UIImage(data: data))
        #expect(result.size.width == 1024)
        #expect(result.size.height == 683)
    }

    @Test func keepsPortraitOrientation() throws {
        let data = try #require(ImageResizer.jpegData(from: image(width: 1500, height: 3000)))
        let result = try #require(UIImage(data: data))
        #expect(result.size.height == 1024)
        #expect(result.size.width == 512)
    }

    @Test func neverEnlargesSmallPhotos() throws {
        let data = try #require(ImageResizer.jpegData(from: image(width: 400, height: 300)))
        let result = try #require(UIImage(data: data))
        #expect(result.size == CGSize(width: 400, height: 300))
    }

    @Test func rejectsDataThatIsNotAnImage() {
        #expect(ImageResizer.jpegData(from: Data("hello".utf8)) == nil)
    }
}
