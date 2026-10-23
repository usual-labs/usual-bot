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

    @Test func thumbnailsDecodeImagesAndIgnoreOtherData() throws {
        #expect(AttachmentTile.thumbnail(of: try image(.png)) != nil)
        #expect(AttachmentTile.thumbnail(of: Data("not an image".utf8)) == nil)
    }
}
