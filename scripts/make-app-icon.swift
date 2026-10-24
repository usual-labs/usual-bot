import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Makes the app icon and the Hermes mark from the full-size doodle, which stays out of git:
//
//   swift scripts/make-app-icon.swift design/avatars/2026-10-24-hermes/png/hermes-doodle.png <out-dir>
//
// Then copy icon-*.png into App/Assets.xcassets/AppIcon.appiconset, mark-120/240/360.png into
// LaunchMark.imageset as mark@1x/2x/3x.png, and mark-512.png to
// Packages/UsualUI/Sources/UsualUI/Resources/hermes-mark.png.
let args = CommandLine.arguments
let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let art = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let out = URL(fileURLWithPath: args[2])

// The drawing's opaque bounds in the 1254 px source (verification.json): x 119…1224, y 103…1160.
let bounds = CGRect(x: 119, y: 103, width: 1105, height: 1057)

func write(_ size: Int, _ name: String, background: Bool, fill: CGFloat) {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: background ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    if background {
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    // Scale so the drawing's longer side fills `fill` of the square, centred.
    let scale = CGFloat(size) * fill / max(bounds.width, bounds.height)
    let drawn = CGSize(width: CGFloat(art.width) * scale, height: CGFloat(art.height) * scale)
    // CG's origin is bottom-left: flip the bounds' top offset.
    let midX = (bounds.midX) * scale, midY = (CGFloat(art.height) - bounds.midY) * scale
    let origin = CGPoint(x: CGFloat(size) / 2 - midX, y: CGFloat(size) / 2 - midY)
    context.draw(art, in: CGRect(origin: origin, size: drawn))
    let destination = CGImageDestinationCreateWithURL(
        out.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

// App icon: opaque, the drawing at 78% so the rounded mask never clips it.
for size in [16, 32, 64, 128, 256, 512, 1024] { write(size, "icon-\(size).png", background: true, fill: 0.78) }
// Mark: transparent, the drawing filling the square.
for size in [120, 240, 360, 512] { write(size, "mark-\(size).png", background: false, fill: 1) }
