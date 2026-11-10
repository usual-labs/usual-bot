import Foundation

extension AppModel {
    /// Lists the gateway's rooms and catches up any that have new events. Returns `nil` when the
    /// gateway couldn't list them, or a room was edited while it did, so the sidebar keeps the
    /// rooms it has.
    func refreshRooms(on channel: JSONRPCChannel) async -> [Contact]? {
        let edits = roomEdits
        guard let result = try? await channel.call("groups.list", params: ["limit": 200]),
            case .array(let rows) = result["rooms"], edits == roomEdits
        else { return nil }
        let summaries = rows.compactMap(RoomSummary.init)
        var listed: [Contact.ID: RoomThread] = [:]
        for summary in summaries {
            let room = roomThread(for: summary)
            listed[RoomSummary.contactID(summary.id)] = room
            // A room asking for approval writes no event, so one at work is read until it's done.
            if summary.latestSeq > room.cursor || room.phase != .ready || room.activity != .idle {
                Task { await room.sync() }
            }
        }
        // A room deleted elsewhere takes its draft with it.
        for room in contacts where room.kind != .agent && listed[room.id] == nil { drafts.forget(room.id) }
        rooms = listed
        return summaries.map(Contact.init(room:))
    }

    /// The room behind `summary`, kept across refreshes so its transcript stays loaded.
    private func roomThread(for summary: RoomSummary) -> RoomThread {
        let id = RoomSummary.contactID(summary.id)
        let room = rooms[id] ?? makeRoom(summary, id: id)
        room.update(summary)
        room.isVisible = id == visibleContactID
        return room
    }

    private func makeRoom(_ summary: RoomSummary, id: Contact.ID) -> RoomThread {
        let room = RoomThread(summary: summary, channel: { [weak self] in self?.channel })
        wireAlerts(of: room, id: id)
        return room
    }

    /// Creates a room with `agents`, two to six of this gateway's agents, and lists it at once.
    /// `lead` picks who answers a message without an @mention, when `routing` is `.lead`. Returns
    /// the room's contact ID, to open it.
    public func createRoom(
        named name: String, agents: [Contact], routing: RoomRouting = .everyone, lead: Contact? = nil
    ) async throws -> Contact.ID {
        let profiles = agents.map { $0.details?.profile ?? $0.id }
        // A new room seats each Bot under its profile name, so that's the lead's member ID.
        let settings = RoomSettings(routing: routing, leadID: lead.map { $0.details?.profile ?? $0.id })
        if isDemo {
            #if DEBUG
                return addDemoRoom(named: name, profiles: profiles, settings: settings)
            #endif
        }
        guard let channel else { throw GatewayError.disconnected }
        let summary = try await RoomThread.create(named: name, profiles: profiles, on: channel)
        let contact = Contact(room: summary)
        let room = roomThread(for: summary)
        rooms[contact.id] = room
        contacts.removeAll { $0.id == contact.id }
        contacts.append(contact)
        if settings.routing != .everyone {
            // The room exists by now, so a refusal is said in it rather than failing the sheet.
            do {
                try await RoomThread.setRouting(settings, roomID: summary.id, on: channel)
            } catch {
                room.addNotice(
                    String(
                        localized:
                            "The room was made, but everyone answers in it for now: who answers wasn't saved. \(Self.describe(error))"
                    ))
            }
        }
        Task { await room.sync() }
        return contact.id
    }

    /// The ways of choosing who answers that a new room can start with; empty where the gateway's
    /// Hermes has none. A room already read says exactly. Without one, `groups.capabilities` lists
    /// the calls: `groups.context` sets the routing, and `auto` came with `groups.continue`.
    public func newRoomRouting() async -> [RoomRouting] {
        if isDemo { return RoomRouting.allCases }
        if let known = rooms.values.first(where: { $0.settings != nil })?.routingModes {
            // The room's own choice is listed even where the gateway no longer takes it.
            return known.isEmpty ? [] : RoomRouting.allCases.filter(known.contains)
        }
        guard let channel, let result = try? await channel.call("groups.capabilities", params: [:]),
            case .array(let listed) = result["methods"], listed.contains("groups.context")
        else { return [] }
        return listed.contains("groups.continue") ? RoomRouting.allCases : [.everyone, .lead]
    }

    /// Why a room can't be changed right now, such as being offline; `nil` when it can.
    public var roomEditingUnavailable: String? {
        if isDemo { return nil }
        switch link {
        case .online: return nil
        case .connecting: return String(localized: "Connecting to the gateway. Try again in a moment.")
        case .offline:
            return String(localized: "You're offline. Rooms can be changed once the gateway is back.")
        }
    }

    /// Saves a room's purpose, notes and who answers, for everyone in it.
    public func saveRoomSettings(_ contact: Contact, _ settings: RoomSettings) async throws {
        guard let room = rooms[contact.id], settings != room.settings else { return }
        if isDemo {
            room.adopt(settings)
            return
        }
        guard let channel else { throw GatewayError.disconnected }
        try await room.save(settings, on: channel)
        Task { await room.sync() }
    }

    /// Renames a room for everyone in it.
    public func renameRoom(_ contact: Contact, to name: String) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let room = rooms[contact.id], !name.isEmpty, name != contact.name else { return }
        if !isDemo {
            guard let channel else { throw GatewayError.disconnected }
            try await room.rename(to: name, on: channel)
        }
        roomEdits += 1
        room.adoptName(name)
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) { contacts[index].name = name }
        Task { await room.sync() }
    }

    /// Stops a room and deletes it and its messages for good. Its agents and their chats stay.
    public func deleteRoom(_ contact: Contact) async throws {
        guard let room = rooms[contact.id] else { return }
        if !isDemo {
            guard let channel else { throw GatewayError.disconnected }
            try await room.disband(on: channel)
        }
        roomEdits += 1
        rooms[contact.id] = nil
        drafts.forget(contact.id)
        contacts.removeAll { $0.id == contact.id }
        sections.move(contact, to: nil)
        sections.setPinned(false, contact)
    }

    #if DEBUG
        /// The demo has no gateway: a new room starts empty, and its members don't answer.
        private func addDemoRoom(named name: String, profiles: [String], settings: RoomSettings) -> Contact.ID {
            let members: [JSONValue] = profiles.map {
                ["member_id": .string($0), "profile": .string($0), "handle": .string($0)]
            }
            let summary = RoomSummary([
                "room_id": .string("demo-\(UUID().uuidString.prefix(8).lowercased())"), "name": .string(name),
                "members": .array(members), "updated_at": .number(Date.now.timeIntervalSince1970),
            ])!
            let contact = Contact(room: summary)
            rooms[contact.id] = RoomThread.sample(summary, events: [], settings: settings)
            contacts.append(contact)
            return contact.id
        }
    #endif
}
