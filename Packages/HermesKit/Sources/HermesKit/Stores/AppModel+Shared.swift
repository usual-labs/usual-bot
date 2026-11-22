import Foundation

/// What the share extension left for the app (`SharedInbox`): you choose a chat for it here, and
/// it goes into that chat's message box for you to send.
extension AppModel {
    /// The item to choose a chat for: the oldest, once you're signed in.
    public var sharedItem: SharedItem? {
        isSignedIn && !shared.isPutOff ? shared.items.first : nil
    }

    /// Reads what's waiting in the shared folder. Called when the share extension opens the app
    /// and when the app comes to the front.
    public func lookForSharedItems() {
        shared.load()
    }

    /// Closed without choosing: it waits until the app next comes to the front.
    public func putOffShared() {
        shared.isPutOff = true
    }

    /// The Bots and rooms an item can go to: the sidebar's, in its order.
    public var shareTargets: [Contact] {
        sections.ordered(sidebarContacts)
    }

    /// Puts `item` in `contact`'s message box, after anything already typed there, with its files
    /// beside it, and opens the chat. Returns why it couldn't, leaving the item where it was.
    @discardableResult
    public func putShared(_ item: SharedItem, in contact: Contact) -> String? {
        if let problem = item.problem(sendingTo: contact) { return problem }
        var attachments: [Attachment] = []
        for name in item.files {
            guard let url = shared.fileURL(name, of: item),
                let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else { return String(localized: "\(name) is no longer on this device.") }
            attachments.append(.converting(name: name, data: data))
        }
        if let text = item.text.nonBlank {
            let typed = drafts[contact.id]
            drafts[contact.id] = typed.nonBlank == nil ? text : typed + "\n\n" + text
        }
        if !attachments.isEmpty { thread(for: contact).returnedAttachments += attachments }
        shared.remove(item)
        requestedContactID = contact.id
        return nil
    }

    /// Deletes an item without putting it anywhere.
    public func discardShared(_ item: SharedItem) {
        shared.remove(item)
    }
}
