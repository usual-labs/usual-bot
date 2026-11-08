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
}
