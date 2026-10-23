import Foundation
import HermesKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import UsualUI

struct AttachmentLoaderTests {
    /// A 4×4 image encoded as `type`.
    private func image(_ type: UTType) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func photosBecomeJPEGsTheAgentCanSee() throws {
        let attachment = AttachmentLoader.make(name: "IMG_0042.HEIC", data: try image(.heic))
        #expect(attachment.name == "IMG_0042.jpg")
        #expect(attachment.kind == .image)
        #expect(attachment.data.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test func otherFilesAreSentAsTheyAre() throws {
        let png = try image(.png)
        #expect(AttachmentLoader.make(name: "chart.png", data: png).data == png)
        let pdf = Data("%PDF-1.7".utf8)
        let attachment = AttachmentLoader.make(name: "report.pdf", data: pdf)
        #expect(attachment.data == pdf)
        #expect(attachment.kind == .file)
    }

    @Test func replyImagesKeepTheirShape() {
        let limit = CGSize(width: 420, height: 360)
        // A square picture is as tall as the limit allows, and no wider.
        #expect(
            MediaLoading.displaySize(pixels: CGSize(width: 1024, height: 1024), limit: limit)
                == CGSize(width: 360, height: 360))
        #expect(
            MediaLoading.displaySize(pixels: CGSize(width: 1200, height: 640), limit: limit)
                == CGSize(width: 420, height: 224))
        #expect(
            MediaLoading.displaySize(pixels: CGSize(width: 600, height: 1600), limit: limit)
                == CGSize(width: 135, height: 360))
        // Small images show at their own size.
        #expect(
            MediaLoading.displaySize(pixels: CGSize(width: 64, height: 48), limit: limit)
                == CGSize(width: 32, height: 24))
    }

    @Test func thumbnailsDecodeImagesAndIgnoreOtherData() throws {
        #expect(MediaLoading.image(try image(.png), maxPixels: 400) != nil)
        #expect(MediaLoading.image(Data("not an image".utf8), maxPixels: 400) == nil)
    }
}
