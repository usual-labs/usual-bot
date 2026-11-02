import Foundation

/// What the gateway part of a message search is doing, for a line under the results.
public enum MessageSearchStatus: Equatable, Sendable {
    /// Nothing to say: no search, the gateway answered, or it can't search (said nowhere).
    case idle
    /// Waiting for the gateway to search older messages.
    case searching
    /// Not connected, so only what this device holds is searched.
    case offline
}

extension AppModel {
    /// Messages in every chat and room that hold all of `query`'s words, at most `limit`, newest
    /// first, then the gateway's finds in history this device doesn't hold (`lookUpMessages`).
    /// Messages with no time (an old cache's) come last, chats in order of last activity. The device
    /// searches each chat's history once loaded (the offline cache's last messages until then) and
    /// each room's log. Empty for a query too short to search.
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
        let local = Array(hits.prefix(limit))
        let earlier = earlierHits(for: query, in: contacts, besides: local + undated)
        return local + earlier + undated.prefix(max(0, limit - local.count))
    }

    /// The gateway's finds for `query`, less the ones this device's own search has: a chat whose
    /// whole history is loaded has all its matches already, and a find that turns out to be
    /// loaded becomes an ordinary result.
    private func earlierHits(for query: String, in contacts: [Contact], besides local: [MessageHit]) -> [MessageHit] {
        guard gatewaySearch.query == Self.trimmed(query) else { return [] }
        return contacts.compactMap { contact in
            guard let hit = gatewaySearch.hits[contact.id] else { return nil }
            guard let thread = threads[contact.id] else { return hit }
            if thread.hasFullHistory { return nil }
            guard let message = loadedMessage(matching: hit, in: thread.state.items) else { return hit }
            if local.contains(where: { $0.contactID == contact.id && $0.itemID == message.itemID }) { return nil }
            return MessageHit(
                contactID: hit.contactID, itemID: message.itemID, author: hit.author, date: message.date,
                snippet: hit.snippet, matches: hit.matches)
        }
    }

    /// Whether the gateway part of a search for `query` is still going, or can't happen.
    public func messageSearchStatus(_ query: String) -> MessageSearchStatus {
        guard MessageSearch(query) != nil else { return .idle }
        guard case .online = link else { return .offline }
        return gatewaySearch.query == Self.trimmed(query) && !gatewaySearch.waiting.isEmpty ? .searching : .idle
    }

    /// Asks the gateway, once typing pauses, for messages matching `query` in the Bot Chats this
    /// device holds only part of. Replaces the search before it; a query too short to search just
    /// ends it. Each agent's find joins `searchMessages` as it arrives. A gateway without the
    /// search endpoint, or one that's offline, leaves the search to this device, silently.
    public func lookUpMessages(_ query: String) {
        gatewaySearch.clear()
        let trimmed = Self.trimmed(query)
        guard let search = MessageSearch(trimmed), !gatewaySearch.isUnsupported, case .online = link else { return }
        let targets = contacts.filter { contact in
            contact.kind == .agent && contact.chatID != nil && threads[contact.id]?.hasFullHistory != true
        }
        guard !targets.isEmpty else { return }
        gatewaySearch.start(trimmed, waitingOn: Set(targets.map(\.id)))
        let delay = gatewaySearch.delay
        gatewaySearch.task = Task { [weak self] in
            // The pause in typing: a new query cancels this before anything is sent.
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            await self?.ask(targets, for: trimmed, search: search)
        }
    }

    private func ask(_ targets: [Contact], for query: String, search: MessageSearch) async {
        await withTaskGroup(of: (Contact, Result<[GatewaySearchResult], any Error>).self) { group in
            var queue = targets[...]
            func next() {
                guard let contact = queue.popFirst() else { return }
                let profile = contact.details?.profile ?? contact.id
                group.addTask { [weak self] in
                    guard let self else { return (contact, .success([])) }
                    do {
                        return (contact, .success(try await fetchSearch(profile: profile, query: query)))
                    } catch {
                        return (contact, .failure(error))
                    }
                }
            }
            for _ in 0..<GatewaySearch.concurrency { next() }
            for await (contact, result) in group {
                guard !Task.isCancelled else { return }
                switch result {
                case .success(let results):
                    let found = results.first { $0.isInBotChat(contact.chatID ?? "") && $0.role != nil }
                    gatewaySearch.receive(found?.hit(in: contact.id, query: search), for: contact.id, query: query)
                case .failure(GatewayError.http(status: let status, let message))
                where (status == 404 && message?.hasPrefix("Profile") != true) || status == 405:
                    // An older Hermes without the endpoint (its `/api/sessions/{id}` route answers
                    // "Session not found"): search on this device only from now on. A profile
                    // removed meanwhile answers "Profile '…' does not exist." and only skips it.
                    gatewaySearch.isUnsupported = true
                    gatewaySearch.clear()
                    group.cancelAll()
                    return
                case .failure:
                    gatewaySearch.receive(nil, for: contact.id, query: query)
                }
                next()
            }
        }
    }

    private func fetchSearch(profile: String, query: String) async throws -> [GatewaySearchResult] {
        if let fetch = gatewaySearch.fetch { return try await fetch(profile, query) }
        guard let auth else { throw GatewayError.disconnected }
        let escape = { (text: String) in
            text.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? text
        }
        let path =
            "/api/sessions/search?q=\(escape(query))&profile=\(escape(profile))&limit=\(GatewaySearch.resultLimit)"
        return try await auth.json(GatewaySearchResult.Page.self, path: path, timeout: 20).results
    }

    /// Where `hit` is in its chat: at once for a message already on screen; for one the gateway
    /// found, once the chat has loaded its history from the gateway.
    public func locate(_ hit: MessageHit) async -> MessageLocation {
        if let itemID = hit.itemID { return .item(itemID) }
        guard let contact = contacts.first(where: { $0.id == hit.contactID }) else {
            return .unavailable(String(localized: "That chat is no longer on the gateway."))
        }
        let thread = thread(for: contact)
        #if DEBUG
            if isDemo { await thread.loadDemoHistory() }
        #endif
        let deadline = ContinuousClock.now + .seconds(30)
        while !thread.hasFullHistory {
            if thread.historyOmitted {
                return .unavailable(
                    String(
                        localized: "\(contact.name)'s chat is too long to load here, so this message can't be shown."))
            }
            if case .failed(let problem) = thread.phase { return .unavailable(problem) }
            if case .offline = link {
                return .unavailable(
                    String(localized: "Usual Bot isn't connected to the gateway, so it can't load this message yet."))
            }
            guard ContinuousClock.now < deadline else {
                return .unavailable(
                    String(localized: "\(contact.name)'s chat is taking too long to load. Try again in a moment."))
            }
            openThread(for: contact)
            // Waits for the chat to attach, which can take seconds for a long one.
            guard (try? await Task.sleep(for: .milliseconds(200))) != nil else {
                return .unavailable(String(localized: "Stopped looking for the message."))
            }
        }
        guard let message = loadedMessage(matching: hit, in: thread.state.items) else {
            return .unavailable(
                String(localized: "Couldn't find this message in \(contact.name)'s chat. It may have been removed."))
        }
        return .item(message.itemID)
    }

    /// The loaded message the gateway's snippet came from: by the same author, holding nearly all
    /// of its words (the snippet's ends can cut a word), the newest if several do.
    func loadedMessage(matching hit: MessageHit, in items: [TranscriptItem]) -> MessageIndex.Message? {
        guard !hit.needle.isEmpty else { return nil }
        let needles = hit.needle.map { Array($0.utf8) }
        var best: (message: MessageIndex.Message, score: Int)?
        for message in messageIndex.messages(of: hit.contactID, items: items) where message.author.wrote(hit) {
            let score = needles.count { MessageSearch.contains($0, in: message.folded) }
            if score >= (best?.score ?? 1) { best = (message, score) }
        }
        guard let best, Double(best.score) >= Double(needles.count) * 0.8 else { return nil }
        return best.message
    }

    private static func trimmed(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension MessageIndex.Author {
    fileprivate func wrote(_ hit: MessageHit) -> Bool {
        switch (self, hit.author) {
        case (.you, .you), (.agent, .agent): true
        default: false
        }
    }
}
