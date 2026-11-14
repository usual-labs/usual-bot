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

/// One group of sidebar rows in order: the pinned chats, a section, or with no `section` whatever
/// isn't in one.
public struct SidebarBlock: Identifiable, Hashable, Sendable {
    public static let unassignedID = "unassigned"
    public static let pinnedID = "pinned"

    public let section: ContactSection?
    public let contacts: [Contact]
    /// The pinned chats, which come first and leave their sections while they're pinned.
    public let isPinned: Bool

    public init(section: ContactSection?, contacts: [Contact]) {
        self.section = section
        self.contacts = contacts
        isPinned = false
    }

    private init(pinned contacts: [Contact]) {
        section = nil
        self.contacts = contacts
        isPinned = true
    }

    public var id: String { isPinned ? Self.pinnedID : section?.id ?? Self.unassignedID }
    public var needsYou: Bool { contacts.contains { $0.activity == .needsYou } }
    public var unreadCount: Int { contacts.reduce(0) { $0 + $1.unreadCount } }

    /// The sidebar's groups for `contacts`: the pinned ones if any, each of `sections`, then what's
    /// left, including anything filed under a section this device doesn't have. With no sections
    /// what isn't pinned is one block, and the sidebar shows no headings.
    public static func blocks(
        for contacts: [Contact], in sections: [ContactSection], pinOrder: [Contact.ID] = []
    ) -> [SidebarBlock] {
        let ordered = ordered(contacts, pinOrder: pinOrder)
        let pinned = ordered.filter(\.isPinned)
        let unpinned = ordered.filter { !$0.isPinned }
        let known = Set(sections.map(\.id))
        var blocks = pinned.isEmpty ? [] : [SidebarBlock(pinned: pinned)]
        blocks += sections.map { section in
            SidebarBlock(section: section, contacts: unpinned.filter { $0.sectionID == section.id })
        }
        let rest = unpinned.filter { contact in contact.sectionID.map { !known.contains($0) } ?? true }
        if !rest.isEmpty || sections.isEmpty { blocks.append(SidebarBlock(section: nil, contacts: rest)) }
        return blocks
    }

    /// Sidebar order: the pinned chats where they were put, then the rest by their newest message
    /// (`Contact.rosterOrder`). A pinned chat not in `pinOrder` yet follows those that are.
    public static func ordered(_ contacts: [Contact], pinOrder: [Contact.ID]) -> [Contact] {
        let place = Dictionary(pinOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return contacts.sorted { lhs, rhs in
            if lhs.isPinned, rhs.isPinned {
                switch (place[lhs.id], place[rhs.id]) {
                case let (left?, right?) where left != right: return left < right
                case (.some, nil): return true
                case (nil, .some): return false
                default: break
                }
            }
            return Contact.rosterOrder(lhs, rhs)
        }
    }
}

/// How the sidebar is arranged. As in the official app, a Bot's section and whether it's pinned are
/// saved on the Bot, so they follow you between devices and clients, while the list of sections,
/// their order, what's folded and the order of the pinned chats belong to this device, and so do a
/// room's section and pin. A section made elsewhere is rebuilt here from the Bots filed under it.
@MainActor
@Observable
public final class SidebarSections {
    public typealias Save = @MainActor (_ profile: String, _ placement: ContactPlacement) async throws -> Void
    public typealias SavePin = @MainActor (_ profile: String, _ isPinned: Bool) async throws -> Void

    public private(set) var sections: [ContactSection] = []
    /// The IDs of folded blocks, which can include `SidebarBlock.unassignedID`.
    public private(set) var folded: Set<String> = []
    /// What went wrong saving a change, which has been undone. Clear it once shown.
    public var problem: String?
    /// The pinned chats in the order they were put in. A new pin goes last, and so does a Bot first
    /// seen pinned, from another device or before this order was kept. It can hold chats that
    /// aren't listed right now, such as a hidden Bot, which come back to their place.
    public private(set) var pinOrder: [Contact.ID] = []

    private var roomSections: [Contact.ID: String] = [:]
    private var pinnedRooms: Set<Contact.ID> = []
    /// Moves the roster doesn't show yet. The roster is read every few seconds, and a read can
    /// land before the write it should reflect, so a move holds until the roster catches up.
    private var pending: [Contact.ID: Pending<ContactPlacement>] = [:]
    /// Pins and unpins the roster doesn't show yet, held the same way.
    private var pendingPins: [Contact.ID: Pending<Bool>] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var save: Save
    @ObservationIgnored var savePin: SavePin
    @ObservationIgnored private var storageKey: String?
    /// Writes run one at a time, each reading what the last one stored.
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    private struct Pending<Value: Equatable> {
        var value: Value
        /// Set once the write is done: how many more roster reads to hold for. Two, because the
        /// first may have started before the write; after that the gateway's word stands, so a
        /// change made elsewhere at the same time can't leave this one stuck.
        var readsLeft: Int?

        /// Counts a roster read that reports `reported`, and says whether the hold is over.
        mutating func settles(with reported: Value) -> Bool {
            guard let left = readsLeft else { return false }
            readsLeft = left - 1
            return reported == value || left <= 1
        }
    }

    private struct Stored: Codable {
        var sections: [ContactSection]
        var folded: Set<String>
        var roomSections: [Contact.ID: String]
        /// Absent in what a version before pinning stored.
        var pinnedRooms: Set<Contact.ID>?
        /// Absent in what a version before ordering pins stored.
        var pinOrder: [Contact.ID]?
    }

    init(
        defaults: UserDefaults, save: @escaping Save = { _, _ in throw GatewayError.disconnected },
        savePin: @escaping SavePin = { _, _ in throw GatewayError.disconnected }
    ) {
        self.defaults = defaults
        self.save = save
        self.savePin = savePin
    }

    // MARK: - Reading

    /// `contact` as the sidebar shows it, with moves and pins still saving, and a room's section
    /// and pin, applied.
    public func placed(_ contact: Contact) -> Contact {
        var contact = contact
        if contact.kind != .agent {
            contact.sectionID = roomSections[contact.id]
            contact.isPinned = pinnedRooms.contains(contact.id)
        } else {
            if let placement = pending[contact.id]?.value {
                contact.sectionID = placement.id
                contact.sectionName = placement.name
            }
            if let isPinned = pendingPins[contact.id]?.value { contact.isPinned = isPinned }
        }
        return contact
    }

    /// The sidebar's groups for contacts already `placed(_:)` (`SidebarBlock.blocks`).
    public func blocks(for contacts: [Contact]) -> [SidebarBlock] {
        SidebarBlock.blocks(for: contacts, in: sections, pinOrder: pinOrder)
    }

    /// `contacts` in sidebar order, without sections (`SidebarBlock.ordered`).
    public func ordered(_ contacts: [Contact]) -> [Contact] {
        SidebarBlock.ordered(contacts, pinOrder: pinOrder)
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

    /// Pins `contact` after the other pinned chats, or with `false` puts it back where it was filed.
    public func setPinned(_ isPinned: Bool, _ contact: Contact) {
        let id = contact.id
        let place = pinOrder.firstIndex(of: id)
        if contact.kind == .agent {
            guard contact.isPinned != isPinned else { return }
            pendingPins[id] = Pending(value: isPinned)
            arrange(id, pinned: isPinned)
            let profile = contact.details?.profile ?? id
            enqueue { [savePin] in
                try await savePin(profile, isPinned)
            } finished: { [weak self] error in
                guard let self, pendingPins[id]?.value == isPinned else { return }
                if error == nil {
                    pendingPins[id]?.readsLeft = 2
                } else {
                    pendingPins[id] = nil
                    arrange(id, pinned: !isPinned, at: place)
                }
            }
        } else if isPinned != pinnedRooms.contains(id) {
            if isPinned { pinnedRooms.insert(id) } else { pinnedRooms.remove(id) }
            arrange(id, pinned: isPinned)
        }
    }

    /// Moves the pinned chat `id` to where `target` is, among the pinned chats `shown` in order.
    public func movePinned(_ id: Contact.ID, to target: Contact.ID, among shown: [Contact.ID]) {
        var shown = shown
        guard let from = shown.firstIndex(of: id), let to = shown.firstIndex(of: target), from != to else { return }
        shown.remove(at: from)
        shown.insert(id, at: to)
        let moved = Set(shown)
        pinOrder = shown + pinOrder.filter { !moved.contains($0) }
        persist()
    }

    /// Adds `id` to the pinned order, at `place` or last, or takes it out.
    private func arrange(_ id: Contact.ID, pinned: Bool, at place: Int? = nil) {
        pinOrder.removeAll { $0 == id }
        if pinned { pinOrder.insert(id, at: min(place ?? pinOrder.count, pinOrder.count)) }
        persist()
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

    /// Takes a fresh roster: settles saved moves and pins, then adopts what other clients did.
    func reconcile(_ contacts: [Contact]) {
        for contact in contacts {
            let reported = ContactPlacement(id: contact.sectionID, name: contact.sectionName)
            if pending[contact.id]?.settles(with: reported) == true { pending[contact.id] = nil }
            if pendingPins[contact.id]?.settles(with: contact.isPinned) == true { pendingPins[contact.id] = nil }
        }
        let shown = contacts.map(placed)
        let adopted = Self.adopting(shown, into: sections)
        let order = Self.pinOrder(pinOrder, for: shown)
        guard adopted != sections || order != pinOrder else { return }
        sections = adopted
        pinOrder = order
        persist()
    }

    /// `order` without the chats `contacts` shows unpinned, and with those it shows pinned that
    /// aren't in it yet added last, most recent first, as they were listed before they had a place.
    static func pinOrder(_ order: [Contact.ID], for contacts: [Contact]) -> [Contact.ID] {
        let unpinned = Set(contacts.filter { !$0.isPinned }.map(\.id))
        var order = order.filter { !unpinned.contains($0) }
        let placed = Set(order)
        order += contacts.filter { $0.isPinned && !placed.contains($0.id) }.sorted(by: Contact.rosterOrder).map(\.id)
        return order
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

    /// A Bot's unsaved move and pin follow it to the ID the gateway renamed it to.
    func renameAgent(from old: Contact.ID, to new: Contact.ID) {
        if let entry = pending.removeValue(forKey: old) { pending[new] = entry }
        if let entry = pendingPins.removeValue(forKey: old) { pendingPins[new] = entry }
        if pinOrder.contains(old) {
            pinOrder = pinOrder.filter { $0 != new }.map { $0 == old ? new : $0 }
            persist()
        }
    }

    /// Drops the unsaved move and pin of a Bot that's gone, and its place among the pinned chats.
    func forget(_ id: Contact.ID) {
        pending[id] = nil
        pendingPins[id] = nil
        if pinOrder.contains(id) { arrange(id, pinned: false) }
    }

    // MARK: - Saving

    private func write(_ placement: ContactPlacement, for contact: Contact) {
        pending[contact.id] = Pending(value: placement)
        let profile = contact.details?.profile ?? contact.id
        enqueue { [save] in
            try await save(profile, placement)
        } finished: { [weak self] error in
            // A newer move of this Bot keeps its own entry.
            guard let self, pending[contact.id]?.value == placement else { return }
            if error == nil { pending[contact.id]?.readsLeft = 2 } else { pending[contact.id] = nil }
        }
    }

    /// Runs `save` after the writes before it, then `finished` with what went wrong, which is also
    /// left in `problem`.
    private func enqueue(
        _ save: @escaping @MainActor () async throws -> Void, finished: @escaping @MainActor ((any Error)?) -> Void
    ) {
        let previous = lastWrite
        lastWrite = Task { [weak self] in
            await previous?.value
            do {
                try await save()
                finished(nil)
            } catch {
                self?.problem = AppModel.describe(error)
                finished(error)
            }
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
        pinnedRooms = stored?.pinnedRooms ?? []
        pinOrder = stored?.pinOrder ?? []
    }

    /// Forgets everything on signing out.
    func clear() {
        if let storageKey { defaults.removeObject(forKey: storageKey) }
        storageKey = nil
        sections = []
        folded = []
        roomSections = [:]
        pinnedRooms = []
        pinOrder = []
        pending = [:]
        pendingPins = [:]
        problem = nil
    }

    private func persist() {
        guard let storageKey else { return }
        let stored = Stored(
            sections: sections, folded: folded, roomSections: roomSections, pinnedRooms: pinnedRooms,
            pinOrder: pinOrder)
        defaults.set(try? JSONEncoder().encode(stored), forKey: storageKey)
    }
}
