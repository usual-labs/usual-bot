import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture you chose for a Bot, made ready for `profiles.set_asset`: the middle square, 256 px,
/// as PNG, as the official app uploads it. That size also keeps it apart from the 160 px still the
/// official app saves of its drawn face (`BotPictures.isDrawnFace`).
public enum BotPictureFile {
    static let edge = 256

    /// `nil` when `data` isn't an image this device can read.
    public static func prepare(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        // A thumbnail as big as the image itself, so ImageIO turns a sideways phone photo upright.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let side = min(image.width, image.height)
        guard side > 0,
            let square = image.cropping(
                to: CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)),
            let context = CGContext(
                data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: edge, height: edge))
        let output = NSMutableData()
        guard let scaled = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
