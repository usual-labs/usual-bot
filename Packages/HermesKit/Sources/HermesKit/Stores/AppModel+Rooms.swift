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
    /// Returns the room's contact ID, to open it.
    public func createRoom(named name: String, agents: [Contact]) async throws -> Contact.ID {
        let profiles = agents.map { $0.details?.profile ?? $0.id }
        if isDemo {
            #if DEBUG
                return addDemoRoom(named: name, profiles: profiles)
            #endif
        }
        guard let channel else { throw GatewayError.disconnected }
        let summary = try await RoomThread.create(named: name, profiles: profiles, on: channel)
        let contact = Contact(room: summary)
        let room = roomThread(for: summary)
        rooms[contact.id] = room
        contacts.removeAll { $0.id == contact.id }
        contacts.append(contact)
        Task { await room.sync() }
        return contact.id
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
        contacts.removeAll { $0.id == contact.id }
        sections.move(contact, to: nil)
    }

    #if DEBUG
        /// The demo has no gateway: a new room starts empty, and its members don't answer.
        private func addDemoRoom(named name: String, profiles: [String]) -> Contact.ID {
            let members: [JSONValue] = profiles.map {
                ["member_id": .string($0), "profile": .string($0), "handle": .string($0)]
            }
            let summary = RoomSummary([
                "room_id": .string("demo-\(UUID().uuidString.prefix(8).lowercased())"), "name": .string(name),
                "members": .array(members), "updated_at": .number(Date.now.timeIntervalSince1970),
            ])!
            let contact = Contact(room: summary)
            rooms[contact.id] = RoomThread.sample(summary, events: [])
            contacts.append(contact)
            return contact.id
        }
    #endif
}
