import Foundation

/// Who answers a room message that @mentions nobody (`groups.state` → `context.routing`). An
/// @mention, `@all` and a routine's post always go straight to the Bots they name.
public enum RoomRouting: String, Sendable, CaseIterable {
    /// Every member answers. Hermes's default, and all an older gateway does.
    case everyone
    /// The lead reads the message first and picks who answers; with no pick, the lead answers.
    case lead
    /// One short model call on the gateway picks; if it fails, everyone answers.
    case auto
}

/// A room's settings. Hermes calls them the room's context and saves all four together
/// (`groups.context`), so changing one sends the others as they are.
public struct RoomSettings: Equatable, Sendable {
    /// One line on what the room is for; every member's turn carries it.
    public var purpose: String
    /// Facts every member should keep in mind.
    public var notes: String
    public var routing: RoomRouting
    /// The lead's member ID. Hermes keeps one only while `routing` is `.lead`.
    public var leadID: String?

    /// As long as the gateway takes (`gateway/hosted_room_context.py`).
    public static let longestPurpose = 500
    public static let mostNotesBytes = 4096

    public init(purpose: String = "", notes: String = "", routing: RoomRouting = .everyone, leadID: String? = nil) {
        self.purpose = purpose
        self.notes = notes
        self.routing = routing
        self.leadID = routing == .lead ? leadID : nil
    }

    /// `groups.state`'s `context`, or a `room.context_set` event's payload.
    init(_ context: JSONValue) {
        self.init(
            purpose: context["purpose"]?.stringValue ?? "", notes: context["notes"]?.stringValue ?? "",
            routing: context["routing"]?.stringValue.flatMap(RoomRouting.init(rawValue:)) ?? .everyone,
            leadID: context["lead_member_id"]?.stringValue?.nonBlank)
    }

    /// Why the gateway would refuse these, before asking it.
    public var problem: String? {
        if purpose.count > Self.longestPurpose {
            return String(localized: "The purpose can be up to \(Self.longestPurpose) characters.")
        }
        if notes.utf8.count > Self.mostNotesBytes {
            return String(localized: "The notes are too long. Hermes keeps up to 4 KB of them.")
        }
        if routing == .lead, leadID == nil { return String(localized: "Pick the Bot that leads.") }
        return nil
    }

    /// `groups.context`'s params. `routes` is off for a gateway whose rooms have a purpose and
    /// notes but no routing: it refuses keys it doesn't know.
    func params(roomID: String, routes: Bool) -> JSONValue {
        var params: [String: JSONValue] = [
            "room_id": .string(roomID), "event_id": .string(UUID().uuidString.lowercased()),
            "purpose": .string(purpose), "notes": .string(notes),
        ]
        if routes {
            params["routing"] = .string(routing.rawValue)
            params["lead_member_id"] = .string(routing == .lead ? leadID ?? "" : "")
        }
        return .object(params)
    }
}

/// A discussion the gateway paused at its cap on rounds or messages (`room.activity` `bounded`),
/// which `groups.continue` gives one more budget.
public struct PausedDiscussion: Identifiable, Equatable, Sendable {
    public enum Limit: Equatable, Sendable {
        case rounds
        case messages
    }

    public var id: String { "\(discussionID):\(grant)" }
    /// The log event ID of the message the Bots were discussing.
    let discussionID: String
    /// Which Continue the next one is, from 1. Hermes allows `max_continues` of them.
    public let grant: Int
    public let limit: Limit
}
