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

    /// The message that goes to the chat: your note, then the text, then the links. A link the
    /// text already spells out isn't repeated.
    public func message(note: String) -> String {
        let said = [note.trimmingCharacters(in: .whitespacesAndNewlines)] + texts
        let extra = links.map(\.absoluteString).filter { link in !said.contains { $0.contains(link) } }
        return (said + extra).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Why this can't go to `contact`, or `nil` when it can. Rooms take text only.
    public func problem(sendingTo contact: Contact) -> String? {
        guard contact.kind != .agent, !files.isEmpty else { return nil }
        return String(localized: "Rooms take text and links only. Pick a Bot to send files.")
    }

    /// What's being shared, in a few words, for the top of the picker.
    public var summary: String {
        var parts: [String] = []
        let images = files.count { Self.sizeLimit(forFileNamed: $0.name) == 25 * 1024 * 1024 }
        let others = files.count - images
        if images == 1 { parts.append(String(localized: "1 image")) }
        if images > 1 { parts.append(String(localized: "\(images) images")) }
        if others == 1 { parts.append(String(localized: "1 file")) }
        if others > 1 { parts.append(String(localized: "\(others) files")) }
        if links.count == 1 { parts.append(links[0].host() ?? links[0].absoluteString) }
        if links.count > 1 { parts.append(String(localized: "\(links.count) links")) }
        if !texts.isEmpty, parts.isEmpty {
            let line = RoomThread.readable(texts.joined(separator: " "))
            return line.count > 120 ? String(line.prefix(120)) + "…" : line
        }
        if !texts.isEmpty { parts.append(String(localized: "text")) }
        return ListFormatter.localizedString(byJoining: parts)
    }
}

extension Attachment {
    /// Photo formats the gateway doesn't take as images; they're converted to JPEG before sending.
    static let convertedExtensions: Set<String> = ["heic", "heif", "tif", "tiff"]
}
