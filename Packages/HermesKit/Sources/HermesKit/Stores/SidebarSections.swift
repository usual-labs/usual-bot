import Foundation
import Observation

/// A named group in the sidebar.
public struct ContactSection: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Where a Bot is filed, as saved on it. Both `nil` means no section.
public struct ContactPlacement: Hashable, Sendable {
    public var id: String?
    public var name: String?

    public init(id: String?, name: String?) {
        self.id = id
        self.name = name
    }
}

/// One group of sidebar rows in order: a section, or with no `section` whatever isn't in one.
public struct SidebarBlock: Identifiable, Hashable, Sendable {
    public static let unassignedID = "unassigned"

    public let section: ContactSection?
    public let contacts: [Contact]

    public init(section: ContactSection?, contacts: [Contact]) {
        self.section = section
        self.contacts = contacts
    }

    public var id: String { section?.id ?? Self.unassignedID }
    public var needsYou: Bool { contacts.contains { $0.activity == .needsYou } }
    public var unreadCount: Int { contacts.reduce(0) { $0 + $1.unreadCount } }
}

/// How the sidebar is grouped. As in the official app, a Bot's section is saved on the Bot, so it
/// follows you between devices and clients, while the list of sections, their order and what's
/// folded belong to this device, and so does a room's section. A section made elsewhere is rebuilt
/// here from the Bots filed under it.
@MainActor
@Observable
public final class SidebarSections {
    public typealias Save = @MainActor (_ profile: String, _ placement: ContactPlacement) async throws -> Void

    public private(set) var sections: [ContactSection] = []
    /// The IDs of folded blocks, which can include `SidebarBlock.unassignedID`.
    public private(set) var folded: Set<String> = []
    /// What went wrong saving a change, which has been undone. Clear it once shown.
    public var problem: String?

    private var roomSections: [Contact.ID: String] = [:]
    /// Moves the roster doesn't show yet. The roster is read every few seconds, and a read can
    /// land before the write it should reflect, so a move holds until the roster catches up.
    private var pending: [Contact.ID: Pending] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var save: Save
    @ObservationIgnored private var storageKey: String?
    /// Writes run one at a time, each reading what the last one stored.
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    private struct Pending {
        var placement: ContactPlacement
        /// Set once the write is done: how many more roster reads to hold for. Two, because the
        /// first may have started before the write; after that the gateway's word stands, so a
        /// move made elsewhere at the same time can't leave this one stuck.
        var readsLeft: Int?
    }

    private struct Stored: Codable {
        var sections: [ContactSection]
        var folded: Set<String>
        var roomSections: [Contact.ID: String]
    }

    init(defaults: UserDefaults, save: @escaping Save = { _, _ in throw GatewayError.disconnected }) {
        self.defaults = defaults
        self.save = save
    }

    // MARK: - Reading

    /// `contact` as the sidebar shows it, with moves still saving and its room section applied.
    public func placed(_ contact: Contact) -> Contact {
        var contact = contact
        if contact.kind != .agent {
            contact.sectionID = roomSections[contact.id]
        } else if let placement = pending[contact.id]?.placement {
            contact.sectionID = placement.id
            contact.sectionName = placement.name
        }
        return contact
    }

    /// The sidebar's groups for contacts already `placed(_:)`: each section, then what's left,
    /// including anything filed under a section this device doesn't have. With no sections,
    /// everything is in the one block and the sidebar shows no headings.
    public func blocks(for contacts: [Contact]) -> [SidebarBlock] {
        let ordered = contacts.sorted(by: Contact.rosterOrder)
        let known = Set(sections.map(\.id))
        var blocks = sections.map { section in
            SidebarBlock(section: section, contacts: ordered.filter { $0.sectionID == section.id })
        }
        let rest = ordered.filter { contact in contact.sectionID.map { !known.contains($0) } ?? true }
        if !rest.isEmpty || sections.isEmpty { blocks.append(SidebarBlock(section: nil, contacts: rest)) }
        return blocks
    }

    public func isFolded(_ blockID: String) -> Bool {
        folded.contains(blockID)
    }

    // MARK: - Changing

    public func toggleFolded(_ blockID: String) {
        if folded.remove(blockID) == nil { folded.insert(blockID) }
        persist()
    }

    /// Files `contact` under a new section and returns it, to name.
    @discardableResult public func create(moving contact: Contact) -> ContactSection {
        let stamp = String(Int(Date.now.timeIntervalSince1970 * 1000), radix: 36)
        let suffix = String(Int.random(in: 0..<60_466_176), radix: 36)
        let section = ContactSection(id: "sec-\(stamp)-\(suffix)", name: String(localized: "New section"))
        sections.append(section)
        persist()
        move(contact, to: section)
        return section
    }

    /// Files `contact` under `section`, or with `nil` takes it out of any.
    public func move(_ contact: Contact, to section: ContactSection?) {
        guard contact.sectionID != section?.id else { return }
        if contact.kind == .agent {
            write(ContactPlacement(id: section?.id, name: section?.name), for: contact)
        } else {
            roomSections[contact.id] = section?.id
            persist()
        }
    }

    /// Renames `section`, and re-saves the name on the Bots in it. Blank keeps the old name.
    public func rename(_ section: ContactSection, to name: String, contacts: [Contact]) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != section.name,
            let index = sections.firstIndex(where: { $0.id == section.id })
        else { return }
        sections[index].name = name
        persist()
        for contact in contacts where contact.kind == .agent && contact.sectionID == section.id {
            write(ContactPlacement(id: section.id, name: name), for: contact)
        }
    }

    /// Moves `section` up (`-1`) or down (`1`) the list.
    public func shift(_ section: ContactSection, by offset: Int) {
        guard let index = sections.firstIndex(where: { $0.id == section.id }),
            sections.indices.contains(index + offset)
        else { return }
        sections.swapAt(index, index + offset)
        persist()
    }

    /// Deletes `section`. What's in it goes to Unassigned, and if a Bot can't be saved there the
    /// next roster read rebuilds the section around it.
    public func delete(_ section: ContactSection, contacts: [Contact]) {
        sections.removeAll { $0.id == section.id }
        folded.remove(section.id)
        roomSections = roomSections.filter { $0.value != section.id }
        persist()
        for contact in contacts where contact.kind == .agent && contact.sectionID == section.id {
            write(ContactPlacement(id: nil, name: nil), for: contact)
        }
    }

    // MARK: - The roster

    /// Takes a fresh roster: settles saved moves, then adopts what other clients did.
    func reconcile(_ contacts: [Contact]) {
        for contact in contacts {
            guard let entry = pending[contact.id], let readsLeft = entry.readsLeft else { continue }
            let reported = ContactPlacement(id: contact.sectionID, name: contact.sectionName)
            pending[contact.id]?.readsLeft = readsLeft - 1
            if reported == entry.placement || readsLeft <= 1 { pending[contact.id] = nil }
        }
        let adopted = Self.adopting(contacts.map(placed), into: sections)
        guard adopted != sections else { return }
        sections = adopted
        persist()
    }

    /// `sections`, plus any its Bots name that aren't there yet, and with the name its Bots give
    /// when they all give the same one. While they differ, a rename is still reaching them.
    static func adopting(_ contacts: [Contact], into sections: [ContactSection]) -> [ContactSection] {
        var names: [String: Set<String>] = [:]
        var order: [String] = []
        for contact in contacts where contact.kind == .agent {
            guard let id = contact.sectionID, let name = contact.sectionName else { continue }
            if names[id] == nil { order.append(id) }
            names[id, default: []].insert(name)
        }
        var adopted = sections.map { section in
            var section = section
            if let agreed = names[section.id], agreed.count == 1, let name = agreed.first { section.name = name }
            return section
        }
        let known = Set(sections.map(\.id))
        for id in order where !known.contains(id) {
            adopted.append(ContactSection(id: id, name: names[id]?.min() ?? id))
        }
        return adopted
    }

    // MARK: - Saving

    private func write(_ placement: ContactPlacement, for contact: Contact) {
        pending[contact.id] = Pending(placement: placement)
        let profile = contact.details?.profile ?? contact.id
        let previous = lastWrite
        lastWrite = Task { [weak self, save] in
            await previous?.value
            do {
                try await save(profile, placement)
                self?.finish(contact.id, placement, error: nil)
            } catch {
                self?.finish(contact.id, placement, error: error)
            }
        }
    }

    private func finish(_ id: Contact.ID, _ placement: ContactPlacement, error: (any Error)?) {
        if let error { problem = AppModel.describe(error) }
        // A newer move of this Bot keeps its own entry.
        guard pending[id]?.placement == placement else { return }
        if error == nil {
            pending[id]?.readsLeft = 2
        } else {
            pending[id] = nil
        }
    }

    /// Waits for the writes so far, for tests.
    func writesFinished() async {
        await lastWrite?.value
    }

    // MARK: - This device

    /// Loads what this device keeps for `gateway`.
    func load(for gateway: GatewayAddress) {
        let key = "sidebarSections-\(gateway.baseURL.absoluteString)"
        storageKey = key
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        sections = stored?.sections ?? []
        folded = stored?.folded ?? []
        roomSections = stored?.roomSections ?? [:]
    }

    /// Forgets everything on signing out.
    func clear() {
        if let storageKey { defaults.removeObject(forKey: storageKey) }
        storageKey = nil
        sections = []
        folded = []
        roomSections = [:]
        pending = [:]
        problem = nil
    }

    private func persist() {
        guard let storageKey else { return }
        let stored = Stored(sections: sections, folded: folded, roomSections: roomSections)
        defaults.set(try? JSONEncoder().encode(stored), forKey: storageKey)
    }
}
