import HermesKit
import SwiftUI

/// Mark as Unread and Mark as Read, for Bot Chats. Rooms have no read time in Hermes to share, so
/// they don't offer either.
struct ReadMarking {
    /// Marks the chat unread, from one of its messages or (`nil`) its row.
    let markUnread: (Contact, TranscriptItem?) -> Void
    let markRead: (Contact) -> Void
}

extension ReadMarking {
    @MainActor init(_ model: AppModel) {
        self.init(markUnread: { model.markUnread($0, from: $1) }, markRead: { model.markRead($0) })
    }

    /// The row's item: Mark as Read while there's something unread, Mark as Unread otherwise.
    @MainActor @ViewBuilder func rowItem(for contact: Contact) -> some View {
        if contact.kind == .agent {
            if contact.hasUnread {
                Button("Mark as Read", systemImage: "envelope.open") { markRead(contact) }
            } else {
                Button("Mark as Unread", systemImage: "envelope.badge") {
                    markUnread(contact, nil)
                    AccessibilityNotification.Announcement(String(localized: "Marked as unread")).post()
                }
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var readMarking: ReadMarking?
}
