import Foundation

extension AppModel {
    /// Messages in every chat and room that hold all of `query`'s words, at most `limit`, newest
    /// first. Messages with no time (an old cache's) come after, chats in order of last activity. Searches what this device holds:
    /// each chat's history once loaded (the offline cache's last messages until then) and each
    /// room's log. Empty for a query too short to search.
    public func searchMessages(_ query: String, limit: Int = 50) -> [MessageHit] {
        guard let search = MessageSearch(query) else { return [] }
        let contacts = self.contacts.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
        messageIndex.keep(only: Set(contacts.map(\.id)))
        var hits: [MessageHit] = []
        var undated: [MessageHit] = []
        for contact in contacts {
            let items: [TranscriptItem]
            var memberName: (String) -> String = { $0 }
            if let thread = threads[contact.id] {
                items = thread.state.items
            } else if let room = rooms[contact.id] {
                items = room.state.items
                memberName = { [contacts] id in
                    let profile = room.state.member(id)?.profile
                    return contacts.first { $0.id == profile && $0.kind == .agent }?.name ?? room.state.name(id)
                }
            } else {
                continue
            }
            for message in messageIndex.messages(of: contact.id, items: items).reversed()
            where search.matches(folded: message.folded) {
                let author: MessageHit.Author
                switch message.author {
                case .you: author = .you
                case .agent: author = .agent
                case .member(let id): author = .member(memberName(id))
                }
                let snippet = search.snippet(of: message.plain)
                let hit = MessageHit(
                    contactID: contact.id, itemID: message.itemID, author: author, date: message.date,
                    snippet: snippet.text, matches: snippet.matches)
                if hit.date == nil { undated.append(hit) } else { hits.append(hit) }
            }
        }
        hits.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return Array((hits + undated).prefix(limit))
    }
}
