import Foundation

/// A file to send with a message: an image the agent looks at, or any other file it can open
/// with its tools.
public struct Attachment: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable, Codable {
        /// Queued for the agent's next turn, which sees it.
        case image
        /// Saved in the chat's workspace and named in the message, so the agent's tools can read it.
        case file
    }

    public let id = UUID()
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    /// Image types the gateway accepts as images. Others, HEIC included, go as files; the app
    /// converts photos to JPEG first.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp"]

    public var kind: Kind {
        Self.imageExtensions.contains((name as NSString).pathExtension.lowercased()) ? .image : .file
    }

    /// The gateway's cap for images; files get the same room as its largest upload (PDFs).
    public var sizeLimit: Int { kind == .image ? 25 * 1024 * 1024 : 50 * 1024 * 1024 }

    public var isTooLarge: Bool { data.count > sizeLimit }

    struct TooLarge: LocalizedError {
        let limit: Int
        var errorDescription: String? {
            String(localized: "It's over the \(limit / 1024 / 1024) MB limit.")
        }
    }
}

/// An attachment as a sent message names it: an `@image:` or `@file:` line after the text, which
/// is also how the gateway's history shows them.
public struct AttachmentRef: Equatable, Sendable, Codable {
    public let kind: Attachment.Kind
    /// The file's path on the gateway, absolute or relative to the chat's workspace.
    public let path: String

    public var name: String { (path as NSString).lastPathComponent }

    /// An image as `prompt.submit`'s `attachments` names it: only the gateway's image types get here.
    var submitted: JSONValue {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["path": .string(path), "mime": .string("image/" + (ext == "jpg" ? "jpeg" : ext))]
    }

    /// The line naming it, quoted the way Hermes reads references back (`format_reference_value`).
    var line: String {
        let prefix = kind == .image ? "@image:" : "@file:"
        guard path.contains(where: { $0.isWhitespace || "()[]{}<>\"'`".contains($0) }) else { return prefix + path }
        guard let quote = ["`", "\"", "'"].first(where: { !path.contains($0) }) else { return prefix + path }
        return prefix + quote + path + quote
    }

    /// Reads one `@image:` or `@file:` line, or Hermes's older `[Image attached at: <path>]`, which
    /// its history passes on as stored when the row lost its image part; `nil` for anything else.
    init?(line: String) {
        let line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix(Self.legacyImagePrefix), line.hasSuffix("]") {
            let path = line.dropFirst(Self.legacyImagePrefix.count).dropLast().trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return nil }
            self.init(kind: .image, path: path)
            return
        }
        let kind: Attachment.Kind
        let value: Substring
        if line.hasPrefix("@image:") {
            (kind, value) = (.image, line.dropFirst("@image:".count))
        } else if line.hasPrefix("@file:") {
            (kind, value) = (.file, line.dropFirst("@file:".count))
        } else {
            return nil
        }
        var path = String(value)
        if let first = path.first, "`\"'".contains(first), path.count > 1, path.last == first {
            path = String(path.dropFirst().dropLast())
        } else if path.contains(where: \.isWhitespace) {
            return nil
        }
        guard !path.isEmpty else { return nil }
        self.init(kind: kind, path: path)
    }

    init(kind: Attachment.Kind, path: String) {
        self.kind = kind
        self.path = path
    }

    private static let legacyImagePrefix = "[Image attached at:"
    /// Hermes's text-only copy of a message adds one per image it carried.
    private static let imagePlaceholder = "[screenshot]"

    /// Splits the attachment lines off the end of a message: what you wrote, and what you sent with it.
    public static func split(_ message: String) -> (text: String, attachments: [AttachmentRef]) {
        var lines = message.components(separatedBy: "\n")
        var attachments: [AttachmentRef] = []
        while let last = lines.last {
            let trimmed = last.trimmingCharacters(in: .whitespaces)
            if let ref = AttachmentRef(line: last) {
                attachments.insert(ref, at: 0)
            } else if trimmed == imagePlaceholder {
                // Dropped only alongside an image: the guard below keeps a message that has none.
            } else if !trimmed.isEmpty || attachments.isEmpty {
                break
            }
            lines.removeLast()
        }
        guard !attachments.isEmpty else { return (message, []) }
        return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), attachments)
    }
}
