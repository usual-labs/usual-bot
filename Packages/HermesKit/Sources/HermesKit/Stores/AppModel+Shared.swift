import Foundation

/// Sending what the share extension left for the app (`SharedOutbox`).
extension AppModel {
    /// Sends what's waiting in the shared folder, if the app is open and connected. Called after
    /// each roster read, and by the app when it comes to the front.
    public func lookForSharedItems() {
        guard shared.container != nil, !shared.isSending, isSignedIn, isForeground else { return }
        Task { await sendShared() }
    }

    /// One pass over the waiting items. An item goes once its chat can take it; one whose chat is
    /// busy stays for the next pass, and one that can't go says why.
    func sendShared() async {
        guard let key = shareKey, !shared.isSending else { return }
        shared.isSending = true
        defer { shared.isSending = false }
        shared.load(for: key)
        // The roster first: a Bot renamed or deleted since the item was shared shows there.
        guard case .online = link, isDemo || rosterReads > 0 else { return }
        for item in shared.items where item.failure == nil {
            // Signed out meanwhile: the folder is empty now.
            guard shareKey == key else { return }
            await send(item)
        }
    }

    /// Tells the share extension who it can send to: the sidebar's contacts in its order.
    func publishShareRoster() {
        guard shared.container != nil, let key = shareKey else { return }
        let listed = sidebarContacts.sorted(by: Contact.rosterOrder)
        let stored = (listed + hiddenBots).reduce(into: [Contact.ID: Data]()) { $0[$1.id] = pictures.data(for: $1.id) }
        shared.publish(
            ShareRoster(
                gateway: key, contacts: listed.map(\.forSharing), hidden: hiddenBots.map(\.forSharing),
                pictures: stored))
    }

    /// The signed-in gateway's name in the shared folder.
    private var shareKey: String? {
        if case .signedIn(let gateway) = session { return gateway.fileName }
        return nil
    }

    private func send(_ item: SharedItem) async {
        let id = currentID(for: item.contactID)
        guard let contact = (contacts + hiddenBots).first(where: { $0.id == id }) else {
            return shared.failed(item, String(localized: "\(item.contactName) isn't on this gateway any more."))
        }
        guard contact.kind == .agent else { return sendToRoom(item, contact) }
        let thread = thread(for: contact)
        openThread(for: contact)
        let deadline = ContinuousClock.now + .seconds(10)
        while thread.phase == .loading, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if case .failed(let reason) = thread.phase { return shared.failed(item, reason) }
        // A reply is running, or the Bot asked something the next message would answer: this
        // isn't a reply to either, so it waits for the chat to be free.
        guard thread.canSendAttachments, thread.questionTheBoxAnswers == nil, let container = shared.container else {
            return
        }
        var attachments: [Attachment] = []
        for name in item.files {
            guard let data = try? Data(contentsOf: container.fileURL(name, of: item), options: .mappedIfSafe) else {
                return shared.failed(item, String(localized: "\(name) is no longer on this device."))
            }
            attachments.append(.converting(name: name, data: data))
        }
        #if DEBUG
            if isDemo, !attachments.isEmpty {
                thread.sendDemo(item.text, attachments: attachments)
                return shared.sent(item)
            }
        #endif
        let before = thread.state.items.count
        if await thread.send(item.text, attachments: attachments) {
            shared.sent(item)
        } else {
            // The chat says why in a notice; the same words go with the item.
            let notices = thread.state.items.dropFirst(before).compactMap { item -> String? in
                if case .notice(let text) = item.content { return text }
                return nil
            }
            shared.failed(item, notices.last ?? String(localized: "The chat couldn't take it."))
        }
    }

    private func sendToRoom(_ item: SharedItem, _ contact: Contact) {
        guard item.files.isEmpty else {
            return shared.failed(item, String(localized: "Rooms take text and links only. Share files to a Bot."))
        }
        // A room the list hasn't caught up on, or still loading: the next pass.
        guard let room = rooms[contact.id] else { return }
        if isDemo { return shared.failed(item, String(localized: "The demo's room can't take messages.")) }
        if !room.driverRunning {
            return shared.failed(
                item, String(localized: "The gateway's room service isn't running, so Bots won't answer."))
        }
        if case .failed(let reason) = room.phase { return shared.failed(item, reason) }
        guard room.canSend else { return }
        // From here the room shows it: a message that doesn't send goes back in its message box.
        room.send(item.text)
        shared.sent(item)
    }
}
