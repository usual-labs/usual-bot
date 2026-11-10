import Foundation
import HermesKit
import UniformTypeIdentifiers

/// Reads what another app handed to the share extension. Files are copied, not read into memory:
/// an extension has little of it, and a file can be 50 MB.
@MainActor
enum ShareLoader {
    /// Sorts `providers` into text, links and files, copying the files into `folder`.
    static func load(_ providers: [NSItemProvider], into folder: URL) async -> SharedContent {
        var content = SharedContent()
        var refused = 0
        for provider in providers {
            switch SharedContent.kind(of: provider.registeredContentTypes) {
            case .file(let type):
                if let file = await file(from: provider, type: type, folder: folder) {
                    content.add(file)
                } else {
                    refused += 1
                }
            case .link:
                if let url = await object(URL.self, from: provider) { content.addLink(url) } else { refused += 1 }
            case .text:
                if let text = await object(String.self, from: provider) { content.addText(text) } else { refused += 1 }
            case .unsupported:
                refused += 1
            }
        }
        if refused > 0 {
            content.problems.append(
                providers.count == 1
                    ? String(localized: "Usual Bot can't take this kind of item.")
                    : String(localized: "Usual Bot can't take \(refused) of these, so they're left out."))
        }
        return content
    }

    private static func object<T: _ObjectiveCBridgeable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
    where T._ObjectiveCType: NSItemProviderReading, T: Sendable {
        guard provider.canLoadObject(ofClass: type) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }

    /// The provider's file, copied into `folder` under the name it would have in Files. One over
    /// the limit isn't copied; its size comes back so the picker can say why it's left out.
    private static func file(from provider: NSItemProvider, type: UTType, folder: URL) async -> SharedContent.File? {
        let suggested = provider.suggestedName
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type) { url, _, _ in
                // The file is gone once this returns, so it's copied here.
                continuation.resume(returning: url.flatMap { copy($0, suggested: suggested, into: folder) })
            }
        }
    }

    private nonisolated static func copy(_ url: URL, suggested: String?, into folder: URL) -> SharedContent.File? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        let name = name(for: url, suggested: suggested)
        guard SharedContent.problem(withFileNamed: name, size: size) == nil else {
            return SharedContent.File(name: name, url: url, size: size)
        }
        let home = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let copy = home.appending(path: name)
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            return nil
        }
        return SharedContent.File(name: name, url: copy, size: size)
    }

    /// Photos names its copies by an ID; the provider's suggested name is the one you know.
    nonisolated static func name(for url: URL, suggested: String?) -> String {
        let ext = url.pathExtension
        guard let base = suggested?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty else {
            return url.lastPathComponent
        }
        let hasIt = (base as NSString).pathExtension.caseInsensitiveCompare(ext) == .orderedSame
        return ext.isEmpty || hasIt ? base : base + "." + ext
    }
}
