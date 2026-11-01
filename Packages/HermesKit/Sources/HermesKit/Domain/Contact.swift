import Foundation

/// One entry in the sidebar: a Hermes profile (an agent) or a hosted room (a group chat).
public struct Contact: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        case agent
        /// A room lists the IDs of its member agents, in the order the gateway reports them.
        case room(memberIDs: [Contact.ID])
    }

    /// What the contact needs from the user right now; drives the sidebar indicator.
    public enum Activity: Hashable, Sendable, Codable {
        case idle
        case working
        case needsYou
    }

    public let id: String
    public var name: String
    public var kind: Kind
    /// Hex colour such as `#6E7BFF` from the profile's `ui_meta['hermes-bots'].color`.
    /// `nil` means the client picks a stable colour from the contact's ID.
    public var tint: String?
    public var preview: String?
    public var lastActive: Date?
    public var unreadCount: Int
    public var activity: Activity
    public var isPinned: Bool
    /// The stored ID of the agent's "Bot Chat" session, when the gateway reported one.
    public var chatID: String?
    /// What the profile panel shows about an agent; `nil` for rooms.
    public var details: AgentDetails?
    /// The agent's own picture on the gateway, set in the official app, or `nil` when it has none
    /// and the client draws one of its own characters. `BotPictures` holds the image itself.
    public var picture: Picture?
    /// The sidebar section this contact is filed under, if any. An agent's comes from the gateway;
    /// a room's stays on this device (`SidebarSections`).
    public var sectionID: String?
    /// The section's name as last saved on the agent, for rebuilding it on another device.
    public var sectionName: String?

    public init(
        id: String,
        name: String,
        kind: Kind = .agent,
        tint: String? = nil,
        preview: String? = nil,
        lastActive: Date? = nil,
        unreadCount: Int = 0,
        activity: Activity = .idle,
        isPinned: Bool = false,
        chatID: String? = nil,
        details: AgentDetails? = nil,
        picture: Picture? = nil,
        sectionID: String? = nil,
        sectionName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.tint = tint
        self.preview = preview
        self.lastActive = lastActive
        self.unreadCount = unreadCount
        self.activity = activity
        self.isPinned = isPinned
        self.chatID = chatID
        self.details = details
        self.picture = picture
        self.sectionID = sectionID
        self.sectionName = sectionName
    }

    /// An agent's own picture (uploaded or generated in the official app) as the roster reports it.
    public struct Picture: Hashable, Sendable, Codable {
        /// The revision of the agent's Bot Mode settings. The official app saves them with every new
        /// picture, so a new revision means the picture may have changed.
        public var revision: Int
        /// The official app marked it a photo, so even a 160 px PNG is the user's picture and not
        /// a still of the app's drawn face.
        public var isPhoto: Bool

        public init(revision: Int, isPhoto: Bool) {
            self.revision = revision
            self.isPhoto = isPhoto
        }
    }
}

/// An agent's profile as the gateway describes it.
public struct AgentDetails: Hashable, Sendable, Codable {
    /// The Hermes profile name, e.g. `default` or `job-scout`.
    public var profile: String
    public var description: String?
    public var model: String?
    public var provider: String?
    public var skillCount: Int?

    public init(
        profile: String, description: String? = nil, model: String? = nil, provider: String? = nil,
        skillCount: Int? = nil
    ) {
        self.profile = profile
        self.description = description
        self.model = model
        self.provider = provider
        self.skillCount = skillCount
    }
}

extension Contact {
    /// Sidebar order: pinned first, then most recently active, then by name.
    /// Contacts that have never been active sort after those that have.
    public static func rosterOrder(_ lhs: Contact, _ rhs: Contact) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        switch (lhs.lastActive, rhs.lastActive) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
