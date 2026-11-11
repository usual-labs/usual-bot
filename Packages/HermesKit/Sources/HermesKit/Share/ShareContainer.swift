import Foundation
import Security

/// Something shared to a Bot or room from another app, waiting for the app to send it.
public struct SharedItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The gateway it was shared for (`GatewayAddress.fileName`), so another sign-in leaves it alone.
    public let gateway: String
    public let contactID: Contact.ID
    /// The Bot's or room's name when it was shared, for saying where it's going.
    public let contactName: String
    /// Your note, then the shared text and links.
    public let text: String
    /// The names of its files, kept beside it.
    public let files: [String]
    public let created: Date
    /// Why the last try didn't send it; `nil` while it waits.
    public var failure: String?

    /// What it is in a few words: its first file, or the start of its text.
    public var title: String {
        if let first = files.first {
            return files.count == 1 ? first : String(localized: "\(first) and \(files.count - 1) more")
        }
        let line = RoomThread.readable(text)
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }
}

/// The Bots and rooms the share extension offers, as the app last saw them.
public struct ShareRoster: Codable, Equatable, Sendable {
    public var gateway: String
    /// In sidebar order, without hidden Bots.
    public var contacts: [Contact]
    /// Hidden Bots, which still show in their rooms' pictures.
    public var hidden: [Contact]
    /// Bots' own pictures, by contact ID.
    public var pictures: [Contact.ID: Data]

    public init(gateway: String, contacts: [Contact], hidden: [Contact] = [], pictures: [Contact.ID: Data] = [:]) {
        self.gateway = gateway
        self.contacts = contacts
        self.hidden = hidden
        self.pictures = pictures
    }

    /// The Bots in a room, for its picture.
    public func members(of contact: Contact) -> [Contact] {
        guard case .room(let ids) = contact.kind else { return [] }
        return ids.compactMap { id in (contacts + hidden).first { $0.id == id } }
    }
}

extension Contact {
    /// What the share extension needs to list a contact: no preview, activity or profile details,
    /// so conversations stay out of the shared folder.
    var forSharing: Contact {
        Contact(id: id, name: name, kind: kind, tint: tint, isPinned: isPinned, picture: picture)
    }
}

/// The folder the app and its share extension both reach, in their App Group. The extension reads
/// the roster from it and leaves what you shared; the app sends that and deletes it. Left out of
/// backups, and emptied on sign-out.
public struct ShareContainer: Sendable {
    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group's folder, or `nil` in a build that has no group: one that isn't signed, or
    /// on the Mac one signed to run locally, where asking for the folder would only raise the
    /// system's question about another app's data.
    public static func appGroup(bundle: Bundle = .main) -> ShareContainer? {
        guard let group = (bundle.object(forInfoDictionaryKey: "UsualShareGroup") as? String)?.nonBlank,
            hasGroup(group),
            let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return ShareContainer(directory: url.appending(path: "Share", directoryHint: .isDirectory))
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

    // MARK: - Roster

    public func roster() -> ShareRoster? {
        (try? Data(contentsOf: rosterURL)).flatMap { try? JSONDecoder().decode(ShareRoster.self, from: $0) }
    }

    func write(_ roster: ShareRoster) throws {
        try prepare(directory)
        try JSONEncoder().encode(roster).write(to: rosterURL, options: Self.writing)
    }

    /// Who you last shared to; the picker starts there.
    public var lastContactID: Contact.ID? {
        (try? String(contentsOf: directory.appending(path: "last"), encoding: .utf8))?.nonBlank
    }

    // MARK: - Items

    /// Everything waiting or failed, oldest first. An item still being written isn't listed.
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

    /// Saves what was shared for `contact`, moving its files in. The item appears once it's whole.
    @discardableResult
    public func add(
        _ content: SharedContent, note: String, to contact: Contact, gateway: String, now: Date = .now
    ) throws -> SharedItem {
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
                id: id, gateway: gateway, contactID: contact.id, contactName: contact.name,
                text: content.message(note: note), files: names, created: now)
            try save(item)
            try? Data(contact.id.utf8).write(to: directory.appending(path: "last"), options: Self.writing)
            return item
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func save(_ item: SharedItem) throws {
        try JSONEncoder().encode(item).write(
            to: folder(of: item.id).appending(path: Self.itemFile), options: Self.writing)
    }

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(of: id))
    }

    func fileURL(_ name: String, of item: SharedItem) -> URL {
        folder(of: item.id).appending(path: name)
    }

    /// Signing out: the roster and everything waiting go.
    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Files

    private static let itemFile = "item.json"
    /// Locked with the device, like the offline cache: both sides write and read only while it's in use.
    private static let writing: Data.WritingOptions = [.atomic, .completeFileProtection]

    private var rosterURL: URL { directory.appending(path: "roster.json") }
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
