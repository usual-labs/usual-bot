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
        let payload = event.payload
        switch event.kind {
        case "message.user":
            if let text = payload["text"]?.stringValue?.nonBlank { append(.user(text)) }
        case "message.member":
            guard let text = payload["text"]?.stringValue?.nonBlank else { return }
            let author = payload["member_id"]?.stringValue ?? event.actorID ?? ""
            append(.member(id: author, text: text))
            let handedTo = mentionedMembers(in: text, excluding: author)
            if !handedTo.isEmpty {
                let names = handedTo.map(name).joined(separator: ", ")
                append(.notice(String(localized: "\(name(author)) handed off to \(names)")))
            }
        case "turn.failed":
            let who = payload["member_id"]?.stringValue.map(name) ?? String(localized: "An agent")
            let error = payload["error"]?.stringValue?.nonBlank
            append(
                .notice(
                    error.map { String(localized: "\(who) couldn't answer: \($0)") }
                        ?? String(localized: "\(who) couldn't answer")))
        case "turn.cancelled":
            if let who = payload["member_id"]?.stringValue.map(name) {
                let reason = payload["reason"]?.stringValue?.nonBlank
                append(
                    .notice(
                        reason.map { String(localized: "\(who) stopped: \($0)") }
                            ?? String(localized: "\(who) stopped")))
            }
        case "turn.deferred":
            let who = payload["member_id"]?.stringValue.map(name) ?? String(localized: "An agent")
            let reason = payload["reason"]?.stringValue?.nonBlank
            append(
                .notice(
                    reason.map { String(localized: "\(who)\u{2019}s turn was put off: \($0)") }
                        ?? String(localized: "\(who)\u{2019}s turn was put off")))
        case "room.activity":
            guard payload["status"]?.stringValue == "bounded" else { return }
            switch payload["reason_code"]?.stringValue {
            case "max_rounds": append(.notice(String(localized: "The discussion reached its round limit")))
            case "max_messages": append(.notice(String(localized: "The discussion reached its message limit")))
            default: append(.notice(String(localized: "The room reached its work limit")))
            }
        case "room.stop_requested":
            append(.notice(String(localized: "Everyone was stopped")))
        case "authority.lost":
            append(.notice(String(localized: "Another gateway now hosts this room")))
        case "member.unavailable":
            let who = (payload["member_id"]?.stringValue ?? event.actorID).map(name) ?? String(localized: "An agent")
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
        items.append(TranscriptItem(id: nextID, content: content))
        nextID += 1
    }
}
