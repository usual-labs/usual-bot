import Foundation

/// An agent seated in a room.
public struct RoomMember: Identifiable, Hashable, Sendable, Codable {
    /// The room's own ID for this member; room events name members by it.
    public let id: String
    /// The Hermes profile behind the member, when it lives on this gateway.
    public let profile: String?
    /// What you @mention it as.
    public let handle: String
    public let displayName: String?

    public init(id: String, profile: String?, handle: String, displayName: String? = nil) {
        self.id = id
        self.profile = profile
        self.handle = handle
        self.displayName = displayName
    }

    init?(_ value: JSONValue) {
        let profile = value["profile"]?.stringValue?.nonBlank
        guard let id = value["member_id"]?.stringValue?.nonBlank ?? profile else { return nil }
        self.init(
            id: id, profile: profile, handle: value["handle"]?.stringValue?.nonBlank ?? profile ?? id,
            displayName: value["display_name"]?.stringValue?.nonBlank)
    }
}

/// One row of `groups.list`: a room hosted on this gateway.
struct RoomSummary: Equatable, Sendable {
    let id: String
    let name: String
    let members: [RoomMember]
    let updatedAt: Date?
    /// Sequence number of the newest event; `0` for an empty log.
    let latestSeq: Int

    init?(_ value: JSONValue) {
        guard let id = value["room_id"]?.stringValue, value["disbanded_at"] == nil else { return nil }
        self.id = id
        name = value["name"]?.stringValue?.nonBlank ?? String(localized: "Room")
        if case .array(let raw) = value["members"] {
            members = raw.compactMap(RoomMember.init)
        } else {
            members = []
        }
        if case .number(let seconds) = value["updated_at"] {
            updatedAt = Date(timeIntervalSince1970: seconds)
        } else {
            updatedAt = nil
        }
        latestSeq = value["latest_seq"]?.intValue ?? 0
    }

    /// Rooms share the sidebar with agents, whose IDs are profile names.
    static func contactID(_ roomID: String) -> Contact.ID { "room:\(roomID)" }
}

extension Contact {
    /// A room as the sidebar lists it.
    init(room summary: RoomSummary) {
        self.init(
            id: RoomSummary.contactID(summary.id), name: summary.name,
            kind: .room(memberIDs: summary.members.compactMap(\.profile)), lastActive: summary.updatedAt)
    }
}

/// One event from a room's log (`groups.log`).
struct RoomEvent: Equatable, Sendable {
    let seq: Int
    let id: String
    let kind: String
    /// `user`, `member`, `gateway` or `system`.
    let actorKind: String
    let actorID: String?
    let payload: JSONValue
    let createdAt: Date

    init?(_ value: JSONValue) {
        guard let seq = value["seq"]?.intValue, let kind = value["kind"]?.stringValue else { return nil }
        self.seq = seq
        id = value["event_id"]?.stringValue ?? "seq-\(seq)"
        self.kind = kind
        actorKind = value["actor"]?["kind"]?.stringValue ?? ""
        actorID = value["actor"]?["id"]?.stringValue
        payload = value["payload"] ?? .null
        if case .number(let seconds) = value["created_at"] {
            createdAt = Date(timeIntervalSince1970: seconds)
        } else {
            createdAt = .distantPast
        }
    }
}
