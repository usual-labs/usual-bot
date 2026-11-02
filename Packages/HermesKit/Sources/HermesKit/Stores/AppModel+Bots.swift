import Foundation

/// What became of a new Bot.
public struct NewBot: Equatable, Sendable {
    public let id: Contact.ID
    /// `false` when Hermes says the Bot has no model it can reply with yet.
    public let canReply: Bool
    /// The Bot was made, but its picture didn't save.
    public let pictureFailed: Bool

    public init(id: Contact.ID, canReply: Bool = true, pictureFailed: Bool = false) {
        self.id = id
        self.canReply = canReply
        self.pictureFailed = pictureFailed
    }
}

extension AppModel {
    /// The longest Bot name the app takes. The gateway has no limit of its own short of 64 KB.
    public static let longestBotName = 80

    /// Why Bots can't be made or changed right now, in words; `nil` when they can.
    public var botEditingUnavailable: String? {
        if isDemo { return nil }
        switch link {
        case .online: return nil
        case .connecting: return String(localized: "Connecting to the gateway. Try again in a moment.")
        case .offline:
            return String(localized: "You're offline. Bots can be made and changed once the gateway is back.")
        }
    }

    /// The profile names on the gateway, which a new Bot can't take.
    public var takenBotNames: Set<String> {
        Set(contacts.filter { $0.kind == .agent }.map { $0.details?.profile ?? $0.id })
    }

    /// The rooms `contact` is a member of.
    public func rooms(including contact: Contact) -> [Contact] {
        contacts.filter { room in
            if case .room(let members) = room.kind { return members.contains(contact.id) }
            return false
        }
    }

    /// `id` as it is now: the new ID of a Bot renamed on the gateway since, or `id` itself.
    public func currentID(for id: Contact.ID) -> Contact.ID {
        var id = id
        var seen: Set<Contact.ID> = []
        while let next = renamedAgents[id], seen.insert(id).inserted { id = next }
        return id
    }

    // MARK: - Making and changing Bots

    /// Makes a Bot named `name`, with an optional description and picture (any image file; it's
    /// cropped and scaled here), and lists it at once. Throws only when the Bot wasn't made.
    public func createBot(_ name: BotName, description: String?, picture: Data?) async throws -> NewBot {
        if let problem = name.problem(taken: takenBotNames) { throw GatewayError.rpc(code: 0, message: problem) }
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank
        let png = picture.flatMap(BotPictureFile.prepare)
        var contact = Contact(
            id: name.profile, name: name.title, preview: description,
            details: AgentDetails(profile: name.profile, description: description))
        var canReply = true
        var pictureFailed = picture != nil && png == nil
        if isDemo {
            #if DEBUG
                addDemoBot(contact)
            #endif
        } else {
            guard let channel else { throw GatewayError.disconnected }
            let profile = try await BotProfiles.create(name, description: description, on: channel)
            contact = Contact(
                id: profile, name: name.title, preview: description,
                details: AgentDetails(profile: profile, description: description))
            // The profile exists from here on, so nothing below undoes it: a name that didn't save
            // shows as the profile's, and the picture can be set again.
            try? await BotMetaWrite.setTitle(name.title, profile: profile, on: channel)
            if let png {
                do {
                    try await BotProfiles.setPicture(png, profile: profile, on: channel)
                } catch {
                    pictureFailed = true
                }
            }
            canReply = await BotProfiles.canReply(profile: profile, on: channel) ?? true
        }
        if let png, !pictureFailed {
            contact.picture = Contact.Picture(revision: -1, isPhoto: true)
            pictures.show(png, for: contact.id)
        }
        rosterHolds.add(contact)
        contacts.removeAll { $0.id == contact.id }
        contacts.append(contact)
        sections.reconcile(contacts)
        return NewBot(id: contact.id, canReply: canReply, pictureFailed: pictureFailed)
    }

    /// Renames a Bot everywhere it shows, in every app. Only its name changes: its profile, and so
    /// its chats, routines and settings, stay as they are.
    public func renameBot(_ contact: Contact, to name: String) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != contact.name else { return }
        if !isDemo {
            guard let channel else { throw GatewayError.disconnected }
            try await BotMetaWrite.setTitle(name, profile: contact.details?.profile ?? contact.id, on: channel)
        }
        rosterHolds.rename(contact.id, to: name)
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) { contacts[index].name = name }
    }

    /// Gives a Bot `picture` (any image file; it's cropped and scaled here) in every app.
    public func setBotPicture(_ contact: Contact, to picture: Data) async throws {
        guard let png = BotPictureFile.prepare(picture) else {
            throw GatewayError.rpc(code: 0, message: String(localized: "That file isn't a picture Usual Bot can read."))
        }
        if !isDemo {
            guard let channel else { throw GatewayError.disconnected }
            try await BotProfiles.setPicture(png, profile: contact.details?.profile ?? contact.id, on: channel)
        }
        pictures.show(png, for: contact.id)
        setPicture(Contact.Picture(revision: -1, isPhoto: true), of: contact.id)
    }

    /// Takes a Bot's picture away, so it shows its drawn face again.
    public func removeBotPicture(_ contact: Contact) async throws {
        if !isDemo {
            guard let channel else { throw GatewayError.disconnected }
            try await BotProfiles.removePicture(profile: contact.details?.profile ?? contact.id, on: channel)
        }
        pictures.forget(contact.id)
        setPicture(nil, of: contact.id)
    }

    /// Whether `contact` can be deleted: the main profile, `default`, can't be.
    public func canDeleteBot(_ contact: Contact) -> Bool {
        contact.kind == .agent && (contact.details?.profile ?? contact.id) != "default"
    }

    /// Deletes a Bot for good, with its chats, routines, skills, memory and keys, and forgets
    /// everything this app kept about it.
    public func deleteBot(_ contact: Contact) async throws {
        guard canDeleteBot(contact) else { return }
        if !isDemo {
            guard let auth else { throw GatewayError.disconnected }
            try await BotProfiles.delete(profile: contact.details?.profile ?? contact.id, auth: auth)
        }
        rosterHolds.remove(contact.id)
        contacts.removeAll { $0.id == contact.id }
        forgetAgent(contact.id)
    }

    private func setPicture(_ picture: Contact.Picture?, of id: Contact.ID) {
        rosterHolds.setPicture(id, picture)
        if let index = contacts.firstIndex(where: { $0.id == id }) { contacts[index].picture = picture }
    }

    // MARK: - Following the gateway

    /// Before a roster read replaces the contacts: moves what this app keeps about a Bot renamed on
    /// the gateway (Hermes lists its old names in `previous_names`) to its new ID, and forgets what
    /// it kept about a Bot that's gone.
    func followProfileChanges(_ rows: [ProfileRow]) {
        let listed = Set(rows.map(\.name))
        // A Bot just made here may not be listed yet.
        let known = Set(contacts.filter { $0.kind == .agent }.map(\.id)).union(threads.keys)
            .subtracting(rosterHolds.added)
        var moved: Set<Contact.ID> = []
        for row in rows {
            for old in row.previousNames where old != row.name && !listed.contains(old) && known.contains(old) {
                moveAgent(from: old, to: row.name)
                moved.insert(old)
            }
        }
        for id in known.subtracting(listed).subtracting(moved) { forgetAgent(id) }
    }

    /// What this app keeps about a Bot under `old` goes under `new`. Its open chat closes and opens
    /// again under the new ID, keeping what it showed; lists reload when next opened.
    func moveAgent(from old: Contact.ID, to new: Contact.ID) {
        renamedAgents[old] = new
        if let thread = threads.removeValue(forKey: old) {
            thread.detach()
            if threads[new] == nil, thread.phase == .ready { threads[new] = makeThread(new, cached: thread.cacheEntry) }
        }
        dropLists(of: old)
        pictures.move(old, to: new)
        sections.renameAgent(from: old, to: new)
        if let index = contacts.firstIndex(where: { $0.id == old }) {
            contacts[index] = contacts[index].renamed(to: new)
        }
        alertsCleared?(old)
        if visibleContactID == old { requestedContactID = new }
    }

    /// Forgets a Bot that's gone: its chat, lists, picture, unsaved section move and alerts. The
    /// offline cache follows at the next save, which writes only what's held here.
    func forgetAgent(_ id: Contact.ID) {
        threads.removeValue(forKey: id)?.detach()
        dropLists(of: id)
        pictures.forget(id)
        sections.forget(id)
        alertsCleared?(id)
        if visibleContactID == id { visibleContactID = nil }
    }

    private func dropLists(of id: Contact.ID) {
        routineLists[id] = nil
        skillLists[id] = nil
        vaultLists[id] = nil
        appLists[id] = nil
        connectorLists[id] = nil
        // Its computer belongs to the old profile; closing it hands control back if you had it.
        screens.removeValue(forKey: id)?.disconnect()
    }

    #if DEBUG
        /// The demo has no gateway: a new Bot gets an empty chat that answers with the scripted reply.
        private func addDemoBot(_ contact: Contact) {
            let thread = ChatThread.sample(contact.id, state: ThreadState(history: [], running: false))
            thread.playsDemoReplies = true
            threads[contact.id] = thread
            routineLists[contact.id] = RoutineList.sample([])
            skillLists[contact.id] = SkillList.sample([])
            vaultLists[contact.id] = VaultList.sample(items: [], sources: [])
        }
    #endif
}

extension Contact {
    /// The same Bot under the ID the gateway gave it after a rename.
    fileprivate func renamed(to id: Contact.ID) -> Contact {
        var details = details
        details?.profile = id
        return Contact(
            id: id, name: name, kind: kind, tint: tint, preview: preview, lastActive: lastActive,
            unreadCount: unreadCount, activity: activity, isPinned: isPinned, chatID: chatID, details: details,
            picture: picture, sectionID: sectionID, sectionName: sectionName)
    }
}
