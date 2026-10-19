import Foundation
@testable import Taleed
import Testing
import UIKit

/// Photos are scaled down to their purpose's box and sent as JPEG (api-guide.md, Uploads).
struct PhotoPreparerTests {
    @Test func boxesPerPurpose() {
        #expect(UploadPurpose.listingPhoto.maxPixelSize == CGSize(width: 1200, height: 1600))
        #expect(UploadPurpose.avatar.maxPixelSize == CGSize(width: 800, height: 800))
        #expect(UploadPurpose.idDocument.maxPixelSize == CGSize(width: 1600, height: 1600))
        #expect(UploadPurpose.reportEvidence.rawValue == "report_evidence")
    }

    @Test func fitsWithinTheBoxKeepingTheRatio() {
        let box = CGSize(width: 1200, height: 1600)
        #expect(PhotoPreparer.fittedSize(CGSize(width: 3024, height: 4032), within: box) == CGSize(width: 1200, height: 1600))
        #expect(PhotoPreparer.fittedSize(CGSize(width: 4032, height: 3024), within: box) == CGSize(width: 1200, height: 900))
        // Never enlarged.
        #expect(PhotoPreparer.fittedSize(CGSize(width: 600, height: 400), within: box) == CGSize(width: 600, height: 400))
    }

    @Test func producesJPEGAtTheTargetSize() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        let jpeg = try PhotoPreparer.jpegData(from: image.pngData()!, purpose: .avatar)
        #expect(jpeg.starts(with: [0xFF, 0xD8]))
        let decoded = try #require(UIImage(data: jpeg))
        #expect(decoded.size.width * decoded.scale == 800)
        #expect(decoded.size.height * decoded.scale == 400)
    }

    @Test func notAnImage() {
        #expect(throws: PhotoPreparer.Failure.notAnImage) {
            try PhotoPreparer.jpegData(from: Data("hello".utf8), purpose: .chatPhoto)
        }
    }
}
