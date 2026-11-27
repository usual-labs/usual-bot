import Foundation

/// Where a file named in a chat comes from.
public enum MediaSource: Hashable, Sendable {
    /// A path on the gateway, read as the message's profile.
    case gateway(String)
    case web(URL)
}

/// A file the ⌥Space panel asked the main window to show beside its chat or room.
public struct FileRequest: Equatable, Sendable {
    public let contactID: Contact.ID
    public let source: MediaSource
    public let name: String
    /// Whose files a gateway path names: the chat's Bot, or a room reply's author.
    public let profile: String?

    public init(contactID: Contact.ID, source: MediaSource, name: String, profile: String?) {
        self.contactID = contactID
        self.source = source
        self.name = name
        self.profile = profile
    }
}
