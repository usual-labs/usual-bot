import Foundation
import Security

/// Something shared from another app, waiting in the app for you to choose a chat for it.
public struct SharedItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The shared text and links.
    public let text: String
    /// The names of its files, kept beside it.
    public let files: [String]
    /// What the share extension left out, and why, one sentence each.
    public let problems: [String]?
    public let created: Date

    /// What it is in a few words: its first file, or the start of its text.
    public var title: String {
        if let first = files.first {
            return files.count == 1 ? first : String(localized: "\(first) and \(files.count - 1) more")
        }
        let line = RoomThread.readable(text)
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }

    /// Rooms take text only.
    public func problem(sendingTo contact: Contact) -> String? {
        guard contact.kind != .agent, !files.isEmpty else { return nil }
        return String(localized: "Rooms take text and links only. Pick a Bot to send files.")
    }
}

/// The folder the app and its share extension both reach, in their App Group. The extension leaves
/// what you shared there and opens the app, which puts it in the chat you choose and deletes it.
/// Left out of backups, and emptied on sign-out.
public struct ShareContainer: Sendable {
    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group's folder, or `nil` in a build that has no group: one that isn't signed, or
    /// on the Mac one signed to run locally, where asking for the folder would only raise the
    /// system's question about another app's data.
    public static func appGroup(bundle: Bundle = .main) -> ShareContainer? {
        guard let group = groupIdentifier(bundle: bundle),
            let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return ShareContainer(directory: url.appending(path: "Share", directoryHint: .isDirectory))
    }

    /// The App Group the app and the extension share, when this build has it.
    static func groupIdentifier(bundle: Bundle = .main) -> String? {
        guard let group = (bundle.object(forInfoDictionaryKey: "UsualShareGroup") as? String)?.nonBlank,
            hasGroup(group)
        else { return nil }
        return group
    }

    private static func hasGroup(_ group: String) -> Bool {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                let groups = SecTaskCopyValueForEntitlement(
                    task, "com.apple.security.application-groups" as CFString, nil) as? [String],
                groups.contains(group)
            else { return false }
            var code: SecCode?
            var staticCode: SecStaticCode?
            var info: CFDictionary?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
                SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
                SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                    == errSecSuccess
            else { return false }
            return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] is String
        #else
            return true
        #endif
    }

    // MARK: - Items

    /// Everything waiting, oldest first. An item still being written isn't listed.
    public func items() -> [SharedItem] {
        let folders =
            (try? FileManager.default.contentsOfDirectory(at: itemsURL, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            (try? Data(contentsOf: folder.appending(path: Self.itemFile))).flatMap {
                try? JSONDecoder().decode(SharedItem.self, from: $0)
            }
        }
        .sorted { ($0.created, $0.id.uuidString) < ($1.created, $1.id.uuidString) }
    }

    /// Saves what was shared, moving its files in. The item appears once it's whole.
    @discardableResult
    public func add(_ content: SharedContent, now: Date = .now) throws -> SharedItem {
        let id = UUID()
        let folder = folder(of: id)
        try prepare(folder)
        do {
            var names: [String] = []
            for file in content.files {
                let name = Self.unused(file.name, among: names)
                let copy = folder.appending(path: name)
                try FileManager.default.copyItem(at: file.url, to: copy)
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete], ofItemAtPath: copy.path)
                names.append(name)
            }
            let item = SharedItem(
                id: id, text: content.message, files: names,
                problems: content.problems.isEmpty ? nil : content.problems, created: now)
            try JSONEncoder().encode(item).write(to: folder.appending(path: Self.itemFile), options: Self.writing)
            return item
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(of: id))
    }

    func fileURL(_ name: String, of item: SharedItem) -> URL {
        folder(of: item.id).appending(path: name)
    }

    /// Signing out: everything that waits goes.
    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Earlier versions kept a list of your Bots here, with their pictures, for the share sheet's
    /// picker. Nothing reads it now.
    func removeLegacyFiles() {
        for name in ["roster.json", "last"] {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    // MARK: - Files

    private static let itemFile = "item.json"
    /// Locked with the device, like the offline cache: both sides write and read only while it's in use.
    private static let writing: Data.WritingOptions = [.atomic, .completeFileProtection]

    private var itemsURL: URL { directory.appending(path: "Items", directoryHint: .isDirectory) }
    private func folder(of id: UUID) -> URL { itemsURL.appending(path: id.uuidString, directoryHint: .isDirectory) }

    private func prepare(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = directory
        try? root.setResourceValues(values)
    }

    /// Two photos can share a name; the second becomes "IMG 2.jpg". The item's own file keeps its name.
    static func unused(_ name: String, among taken: [String]) -> String {
        let name = name.replacingOccurrences(of: "/", with: "-")
        let reserved = taken + [itemFile]
        guard reserved.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        for number in 2... {
            let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            if !reserved.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) { return candidate }
        }
        return name
    }
}
