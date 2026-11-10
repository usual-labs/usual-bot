import Foundation

/// Everything a room shows, built from its event log in sequence order.
public struct RoomState: Equatable, Sendable {
    public private(set) var items: [TranscriptItem] = []
    public private(set) var members: [RoomMember]
    /// The last applied sequence number; the next `groups.log` reads after it.
    private(set) var cursor = 0
    /// Event IDs of your messages, to recognise them when they come back in the log.
    private(set) var seenEventIDs: Set<String> = []
    private var nextID = 0
    /// The routing and lead as the log has them, to say what a change changed.
    private var settings = RoomSettings()
    /// Threads a message was already sent in: a message in one skips routing.
    private var threads: Set<String> = []
    /// The newest message from you or a routine, by its event ID.
    private var newestMessage: String?
    /// Everyone was stopped after `newestMessage`, so its discussion can't carry on.
    private var stopped = false
    /// How many times the newest message's discussion was carried on.
    private var grants = 0
    /// The newest message's discussion, while it's paused at its cap. A later message or a stop
    /// ends the offer: Hermes takes a Continue past another thread's message, but the app shows
    /// one conversation, and it has moved on.
    public private(set) var pause: PausedDiscussion?
    /// The lead, while it reads the newest message to pick who answers. Its status says only that
    /// it's running a turn.
    public private(set) var choosingLead: String?
    /// When the event being applied happened. Set only while applying it, so equal logs give
    /// equal states.
    private var eventDate: Date?

    init(members: [RoomMember]) {
        self.members = members
    }

    public func member(_ id: String) -> RoomMember? {
        members.first { $0.id == id }
    }

    /// Applies events after `cursor`, in order; anything at or before it was applied already.
    mutating func apply(_ events: [RoomEvent]) {
        for event in events.sorted(by: { $0.seq < $1.seq }) where event.seq > cursor {
            apply(event)
            cursor = event.seq
        }
    }

    private mutating func apply(_ event: RoomEvent) {
        seenEventIDs.insert(event.id)
        // An event with no time is dated when it arrived.
        eventDate = event.createdAt == .distantPast ? .now : event.createdAt
        defer { eventDate = nil }
        let payload = event.payload
        switch event.kind {
        case "message.user":
            let text = payload["text"]?.stringValue ?? ""
            let thread = payload["thread_id"]?.stringValue
            choosingLead = goesToLead(text, thread: thread, from: event.actorID) ? settings.leadID : nil
            if let thread { threads.insert(thread) }
            (newestMessage, stopped, grants, pause) = (event.id, false, 0, nil)
            if let text = text.nonBlank { append(.user(text)) }
        case "message.member":
            if let thread = payload["thread_id"]?.stringValue { threads.insert(thread) }
            guard let text = payload["text"]?.stringValue?.nonBlank else { return }
            let author = payload["member_id"]?.stringValue ?? event.actorID ?? ""
            append(.member(id: author, text: text))
            let handedTo = mentionedMembers(in: text, excluding: author)
            if !handedTo.isEmpty {
                let names = handedTo.map(name).joined(separator: ", ")
                append(.notice(String(localized: "\(name(author)) handed off to \(names)")))
            }
        case "turn.failed":
            if payload["discussion_event_id"]?.stringValue == newestMessage { choosingLead = nil }
            let who = payload["member_id"]?.stringValue.map(name) ?? String(localized: "A Bot")
            let error = payload["error"]?.stringValue?.nonBlank
            append(
                .notice(
                    error.map { String(localized: "\(who) couldn't answer: \($0)") }
                        ?? String(localized: "\(who) couldn't answer")))
        case "turn.cancelled":
            if payload["discussion_event_id"]?.stringValue == newestMessage { choosingLead = nil }
            if let who = payload["member_id"]?.stringValue.map(name) {
                let reason = payload["reason"]?.stringValue?.nonBlank
                append(
                    .notice(
                        reason.map { String(localized: "\(who) stopped: \($0)") }
                            ?? String(localized: "\(who) stopped")))
            }
        case "turn.deferred":
            let who = payload["member_id"]?.stringValue.map(name) ?? String(localized: "A Bot")
            let reason = payload["reason"]?.stringValue?.nonBlank
            append(
                .notice(
                    reason.map { String(localized: "\(who)\u{2019}s turn was put off: \($0)") }
                        ?? String(localized: "\(who)\u{2019}s turn was put off")))
        case "room.activity":
            let discussion = payload["discussion_event_id"]?.stringValue
            let isNewest = discussion != nil && discussion == newestMessage
            guard payload["status"]?.stringValue == "bounded" else {
                if isNewest { pause = nil }
                return
            }
            let limit: PausedDiscussion.Limit? =
                switch payload["reason_code"]?.stringValue {
                case "max_rounds": .rounds
                case "max_messages": .messages
                default: nil
                }
            switch limit {
            case .rounds: append(.notice(String(localized: "The discussion reached its round limit")))
            case .messages: append(.notice(String(localized: "The discussion reached its message limit")))
            case nil: append(.notice(String(localized: "The room reached its work limit")))
            }
            if let discussion, let limit, isNewest, !stopped {
                pause = PausedDiscussion(discussionID: discussion, grant: grants + 1, limit: limit)
            }
        case "room.continued":
            if payload["discussion_event_id"]?.stringValue == newestMessage {
                grants += 1
                pause = nil
            }
            append(.notice(String(localized: "The discussion carried on")))
        case "room.context_set":
            let changed = RoomSettings(payload)
            if let notice = notice(for: changed) { append(.notice(notice)) }
            settings = changed
        case "room.assignment":
            if payload["discussion_event_id"]?.stringValue == newestMessage { choosingLead = nil }
            guard let lead = payload["lead_member_id"]?.stringValue else { return }
            // Hermes falls back to the lead alone when its answer names nobody.
            let others = memberIDs(payload["member_ids"]).filter { $0 != lead }.map(name).joined(separator: ", ")
            let takes = memberIDs(payload["member_ids"]).contains(lead)
            if payload["fallback"]?.boolValue == true || others.isEmpty {
                append(.notice(String(localized: "\(name(lead)), the lead, is taking this")))
            } else if takes {
                append(.notice(String(localized: "\(name(lead)), the lead, is taking this with \(others)")))
            } else {
                append(.notice(String(localized: "\(name(lead)), the lead, gave this to \(others)")))
            }
        case "room.routed":
            let chosen = memberIDs(payload["member_ids"]).filter { member($0) != nil }
            if payload["fallback"]?.boolValue == true {
                append(.notice(String(localized: "The room couldn't pick who answers, so everyone will")))
            } else if payload["everyone"]?.boolValue == true {
                append(.notice(String(localized: "The room picked everyone to answer")))
            } else if !chosen.isEmpty {
                // A Bot that has left the room is left out rather than shown as an ID.
                append(
                    .notice(String(localized: "The room picked \(chosen.map(name).joined(separator: ", ")) to answer")))
            }
        case "room.stop_requested":
            (stopped, pause, choosingLead) = (true, nil, nil)
            append(.notice(String(localized: "Everyone was stopped")))
        case "authority.lost":
            append(.notice(String(localized: "Another gateway now hosts this room")))
        case "member.unavailable":
            let who = (payload["member_id"]?.stringValue ?? event.actorID).map(name) ?? String(localized: "A Bot")
            append(.notice(String(localized: "\(who) is unavailable")))
        case "room.renamed":
            if let newName = payload["name"]?.stringValue?.nonBlank {
                append(.notice(String(localized: "Room renamed to “\(newName)”")))
            }
        case "room.members_changed":
            if case .array(let raw) = payload["members"] { members = raw.compactMap(RoomMember.init) }
            append(.notice(String(localized: "Members changed")))
        case "room.disbanded":
            append(.notice(String(localized: "This room was closed")))
        default:
            // turn.started/settled/reassigned, room.created and authority.claimed only move state
            // the room's status reports; they add nothing to read. An agent that passes (settles
            // without replying) leaves no line.
            break
        }
    }

    private func memberIDs(_ value: JSONValue?) -> [String] {
        guard case .array(let raw) = value else { return [] }
        return raw.compactMap(\.stringValue)
    }

    /// Hermes's rule for a message the lead sees first (`routes_through_lead`): a lead room, a new
    /// thread, nobody @mentioned, and not a routine's post.
    private func goesToLead(_ text: String, thread: String?, from actor: String?) -> Bool {
        guard settings.routing == .lead, let lead = settings.leadID, member(lead) != nil else { return false }
        if let actor, actor.hasPrefix("cron:") || actor.hasPrefix("cron-notice:") { return false }
        if let thread, threads.contains(thread) { return false }
        let handles = Set(members.map { $0.handle.lowercased() }).union(["all", "everyone"])
        return !Self.mentions(in: text).contains { handles.contains($0.lowercased()) }
    }

    /// What a change of settings changed, in the room's own words; `nil` when nothing you'd notice.
    private func notice(for changed: RoomSettings) -> String? {
        if changed.routing != settings.routing || changed.leadID != settings.leadID {
            switch changed.routing {
            case .everyone: return String(localized: "Everyone now answers a message without an @mention")
            case .auto: return String(localized: "The room now picks who answers a message without an @mention")
            case .lead:
                let lead = changed.leadID.map(name) ?? String(localized: "A Bot")
                return String(localized: "\(lead) now leads, and picks who answers a message without an @mention")
            }
        }
        if changed.purpose != settings.purpose {
            return changed.purpose.isEmpty
                ? String(localized: "The room's purpose was removed")
                : String(localized: "The room's purpose is now “\(changed.purpose)”")
        }
        return changed.notes != settings.notes ? String(localized: "The room's notes changed") : nil
    }

    /// The name a member shows. Agents use their sidebar name, resolved by the view.
    public func name(_ memberID: String) -> String {
        guard let member = member(memberID) else { return memberID }
        return member.displayName ?? Contact.friendlyName(forProfile: member.profile ?? member.handle)
    }

    /// Members @mentioned in a reply, in room order: the gateway routes the next round to them.
    func mentionedMembers(in text: String, excluding author: String) -> [String] {
        let handles = Set(Self.mentions(in: text).map { $0.lowercased() })
        if handles.contains("all") || handles.contains("everyone") {
            return members.map(\.id).filter { $0 != author }
        }
        return members.filter { handles.contains($0.handle.lowercased()) && $0.id != author }.map(\.id)
    }

    /// `@handle` words, matching the gateway's own mention rule.
    static func mentions(in text: String) -> [String] {
        let pattern = /@([A-Za-z0-9][A-Za-z0-9._:-]*)/
        return text.matches(of: pattern).map { String($0.output.1) }
    }

    mutating func addNotice(_ text: String) {
        append(.notice(text))
    }

    mutating func replaceMembers(_ members: [RoomMember]) {
        self.members = members
    }

    private mutating func append(_ content: TranscriptItem.Content) {
        items.append(TranscriptItem(id: nextID, content: content, date: eventDate ?? .now))
        nextID += 1
    }
}
