import SwiftUI

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// The bundled character images. They are plain PNGs in this package's resources, which
/// `Image(_:bundle:)` doesn't look up (it reads asset catalogs only), so they're loaded by URL
/// once and kept.
@MainActor
enum AvatarArt {
    private static var cache: [String: Image] = [:]

    static func image(_ character: String) -> Image? {
        if let image = cache[character] { return image }
        guard let url = Bundle.module.url(forResource: "avatar-\(character)", withExtension: "png") else { return nil }
        #if canImport(AppKit)
            guard let platformImage = NSImage(contentsOf: url) else { return nil }
            let image = Image(nsImage: platformImage)
        #else
            guard let platformImage = UIImage(contentsOfFile: url.path) else { return nil }
            let image = Image(uiImage: platformImage)
        #endif
        cache[character] = image
        return image
    }
}
