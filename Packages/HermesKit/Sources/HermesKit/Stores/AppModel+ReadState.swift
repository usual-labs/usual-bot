import Foundation

extension AppModel {
    /// The Bot Chats whose read state can be shared: agents with a stored chat and a thread here.
    var readableChats: [ReadSync.Chat] {
        contacts.compactMap { contact in
            guard contact.kind == .agent, let storedID = contact.chatID, let thread = threads[contact.id] else {
                return nil
            }
            return ReadSync.Chat(thread: thread, storedID: storedID, profile: contact.details?.profile ?? contact.id)
        }
    }

    /// Mark as Unread on a Bot Chat, from its row or one of its messages (`from`), which opening it
    /// on this device goes back to. Your other devices and the official app see it through Hermes's
    /// read time; the message stays here, as Hermes has nowhere to keep it. Rooms have no read time
    /// in Hermes, so they don't offer it.
    public func markUnread(_ contact: Contact, from item: TranscriptItem? = nil) {
        guard contact.kind == .agent else { return }
        thread(for: contact).markUnread(from: item)
        readSync.markUnread(contact.id)
    }

    /// Mark as Read on a chat's row: what it has stops counting as unread, on every device.
    public func markRead(_ contact: Contact) {
        guard contact.kind == .agent, let thread = threads[contact.id] else { return }
        thread.markRead()
        alertsCleared?(contact.id)
    }
}
