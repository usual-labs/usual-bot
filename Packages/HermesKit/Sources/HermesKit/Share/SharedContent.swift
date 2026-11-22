import Foundation
import UniformTypeIdentifiers

/// What another app handed to Usual Bot's share extension: text, web links and files, and what it
/// couldn't take.
public struct SharedContent: Equatable, Sendable {
    public struct File: Equatable, Sendable {
        public let name: String
        /// Where the extension's copy is until the item is saved.
        public let url: URL
        public let size: Int

        public init(name: String, url: URL, size: Int) {
            self.name = name
            self.url = url
            self.size = size
        }
    }

    public var texts: [String] = []
    public var links: [URL] = []
    public var files: [File] = []
    /// Why some of it was left out, one plain sentence each.
    public var problems: [String] = []

    public init() {}

    /// Nothing that can be sent.
    public var isEmpty: Bool { texts.isEmpty && links.isEmpty && files.isEmpty }

    /// How a shared item arrives, from the types its provider offers.
    public enum Kind: Equatable, Sendable {
        case file(UTType)
        case link
        case text
        case unsupported
    }

    /// A file wins over a link or text: a text file from Files offers plain text too, and should
    /// arrive as the file. A web link comes before text, since Safari offers a page as both.
    public static func kind(of types: [UTType]) -> Kind {
        let isFile = types.contains { $0.conforms(to: .fileURL) }
        let payload = types.first {
            !$0.conforms(to: .url) && ($0.conforms(to: .data) || $0.conforms(to: .package)) && (isFile || !isText($0))
        }
        if let payload { return .file(payload) }
        if isFile { return .file(.data) }
        if types.contains(where: { $0.conforms(to: .url) }) { return .link }
        if types.contains(where: isText) { return .text }
        return .unsupported
    }

    private static func isText(_ type: UTType) -> Bool { type.conforms(to: .text) }

    /// Images are held to the gateway's image limit even before a photo is converted for sending.
    public static func sizeLimit(forFileNamed name: String) -> Int {
        let ext = (name as NSString).pathExtension.lowercased()
        let isImage = Attachment.imageExtensions.contains(ext) || Attachment.convertedExtensions.contains(ext)
        return (isImage ? 25 : 50) * 1024 * 1024
    }

    /// Why a file of this size can't be sent, or `nil` when it can.
    public static func problem(withFileNamed name: String, size: Int) -> String? {
        let limit = sizeLimit(forFileNamed: name)
        guard size > limit else { return nil }
        let megabytes = max(limit / 1024 / 1024 + 1, Int((Double(size) / 1024 / 1024).rounded()))
        let kind =
            limit == 25 * 1024 * 1024
            ? String(localized: "Images can be up to 25 MB.") : String(localized: "Files can be up to 50 MB.")
        return String(localized: "\(name) is \(megabytes) MB, so it's left out. \(kind)")
    }

    /// Takes a file, or notes why it's left out.
    public mutating func add(_ file: File) {
        if let problem = Self.problem(withFileNamed: file.name, size: file.size) {
            problems.append(problem)
        } else {
            files.append(file)
        }
    }

    public mutating func addText(_ text: String) {
        guard let text = text.nonBlank?.trimmingCharacters(in: .whitespacesAndNewlines), !texts.contains(text) else {
            return
        }
        texts.append(text)
    }

    public mutating func addLink(_ url: URL) {
        if !links.contains(url) { links.append(url) }
    }

    /// What goes in the message box: the text, then the links. A link the text already spells out
    /// isn't repeated.
    public var message: String {
        let extra = links.map(\.absoluteString).filter { link in !texts.contains { $0.contains(link) } }
        return (texts + extra).joined(separator: "\n\n")
    }
}

extension Attachment {
    /// Photo formats the gateway doesn't take as images; they're converted to JPEG before sending.
    static let convertedExtensions: Set<String> = ["heic", "heif", "tif", "tiff"]
}
