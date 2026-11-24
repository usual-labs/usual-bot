import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// What you shared to Usual Bot from other apps, waiting for you to choose a chat for it. The share
/// extension opens the app, which shows the first one (`AppModel.putShared`).
@MainActor
@Observable
public final class SharedInbox {
    public private(set) var items: [SharedItem] = []
    /// Closed without choosing a chat: it's asked again the next time the app comes to the front.
    var isPutOff = false
    /// `nil` in a build without the App Group; then nothing is shared.
    @ObservationIgnored let container: ShareContainer?

    init(container: ShareContainer?) {
        self.container = container
        container?.removeLegacyFiles()
    }

    /// Reads what's in the folder.
    func load() {
        isPutOff = false
        let found = container?.items() ?? []
        if found != items { items = found }
    }

    /// It's in a message box now, or you chose not to send it, so its copy here goes.
    func remove(_ item: SharedItem) {
        container?.remove(item.id)
        items.removeAll { $0.id == item.id }
    }

    func fileURL(_ name: String, of item: SharedItem) -> URL? {
        container?.fileURL(name, of: item)
    }

    /// Forgets everything on signing out.
    func clear() {
        container?.clear()
        items = []
    }
}

extension Attachment {
    /// A file ready for the gateway, which takes PNG, JPEG, GIF, WebP and BMP as images. Photos
    /// (HEIC) and TIFFs are converted to JPEG, so the agent sees them instead of getting a file
    /// it can't open.
    public static func converting(name: String, data: Data) -> Attachment {
        let ext = (name as NSString).pathExtension.lowercased()
        guard convertedExtensions.contains(ext), let jpeg = jpeg(from: data) else {
            return Attachment(name: name, data: data)
        }
        return Attachment(name: ((name as NSString).deletingPathExtension) + ".jpg", data: jpeg)
    }

    /// Re-encodes an image as JPEG, keeping its orientation and metadata.
    private static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImageFromSource(
            destination, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
