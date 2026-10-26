import SwiftUI

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// The bundled character images and the Hermes mark. They are plain PNGs in this package's resources, which
/// `Image(_:bundle:)` doesn't look up (it reads asset catalogs only), so they're loaded by URL
/// once and kept.
@MainActor
enum AvatarArt {
    private static var cache: [String: Image] = [:]
    /// Agents' own pictures, decoded once per change, by contact ID.
    private static var pictures: [String: (data: Data, image: Image)] = [:]

    static func image(_ character: String) -> Image? { resource("avatar-\(character)") }

    /// An agent's own picture (PNG, JPEG or WebP) from the gateway.
    static func picture(_ data: Data, for contactID: String) -> Image? {
        if let cached = pictures[contactID], cached.data == data { return cached.image }
        #if canImport(AppKit)
            guard let platformImage = NSImage(data: data) else { return nil }
            let image = Image(nsImage: platformImage)
        #else
            guard let platformImage = UIImage(data: data) else { return nil }
            let image = Image(uiImage: platformImage)
        #endif
        pictures[contactID] = (data, image)
        return image
    }

    /// Any PNG in the package's resources, by file name without the extension.
    static func resource(_ name: String) -> Image? {
        if let image = cache[name] { return image }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        #if canImport(AppKit)
            guard let platformImage = NSImage(contentsOf: url) else { return nil }
            let image = Image(nsImage: platformImage)
        #else
            guard let platformImage = UIImage(contentsOfFile: url.path) else { return nil }
            let image = Image(uiImage: platformImage)
        #endif
        cache[name] = image
        return image
    }
}
