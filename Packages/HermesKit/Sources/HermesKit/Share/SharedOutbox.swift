import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers
import os

/// What you shared to Usual Bot from other apps and the app hasn't sent yet: waiting for the
/// gateway or the chat, or failed with the reason. `AppModel.lookForSharedItems()` sends them.
@MainActor
@Observable
public final class SharedOutbox {
    public private(set) var items: [SharedItem] = []
    /// `nil` in a build without the App Group; then nothing is shared.
    @ObservationIgnored let container: ShareContainer?
    @ObservationIgnored private var lastRoster: ShareRoster?
    @ObservationIgnored var isSending = false
    /// Set by the app model: try the waiting items now.
    @ObservationIgnored var send: (() -> Void)?

    private static let log = Logger(subsystem: "UsualBot", category: "share")

    init(container: ShareContainer?) {
        self.container = container
    }

    /// Reads what's in the folder for `gateway`.
    func load(for gateway: String) {
        let found = container?.items().filter { $0.gateway == gateway } ?? []
        if found != items { items = found }
    }

    /// Tells the share extension who it can send to, when that changed.
    func publish(_ roster: ShareRoster) {
        guard let container, roster != lastRoster else { return }
        do {
            try container.write(roster)
            lastRoster = roster
        } catch {
            Self.log.error("Couldn't save the share roster: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// It's in the chat now, so its copy here goes.
    func sent(_ item: SharedItem) {
        container?.remove(item.id)
        items.removeAll { $0.id == item.id }
    }

    func failed(_ item: SharedItem, _ reason: String) {
        update(item, failure: reason)
    }

    /// Sends a failed item again.
    public func retry(_ item: SharedItem) {
        update(item, failure: nil)
        send?()
    }

    /// Deletes an item without sending it.
    public func discard(_ item: SharedItem) {
        sent(item)
    }

    /// Forgets everything on signing out.
    func clear() {
        container?.clear()
        items = []
        lastRoster = nil
    }

    private func update(_ item: SharedItem, failure: String?) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].failure = failure
        try? container?.save(items[index])
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
