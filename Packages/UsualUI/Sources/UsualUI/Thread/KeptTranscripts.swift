import HermesKit
import SwiftUI

/// The chats you were in last, kept built out of sight, so going back to one shows it at once
/// instead of building and laying out its messages again: most of a switch (see the known issues).
struct RecentChats: Equatable {
    /// The chat shown and the two before it. Each one kept costs its messages' views in memory and
    /// makes opening a chat that isn't kept a little slower (see the known issues). iPhone pushes a
    /// pane for each chat, so it keeps none.
    #if os(macOS)
        static let limit = 3
    #else
        static let limit = 1
    #endif

    let limit: Int
    /// In the order they were first kept: a chat's place doesn't move as you go back to it, so its
    /// view stays where it is.
    private(set) var ids: [Contact.ID] = []
    /// The least recently shown first.
    private var uses: [Contact.ID] = []

    init(limit: Int = Self.limit) {
        self.limit = max(limit, 1)
    }

    /// Shows `id`, letting go of the chat shown longest ago when there are too many.
    mutating func use(_ id: Contact.ID) {
        if !ids.contains(id) { ids.append(id) }
        uses.removeAll { $0 == id }
        uses.append(id)
        while ids.count > limit, let oldest = uses.first {
            uses.removeFirst()
            ids.removeAll { $0 == oldest }
        }
    }

    /// What's kept once `id` is shown, before `use` has run: the first layout of a switch comes
    /// before `onChange`.
    func showing(_ id: Contact.ID) -> [Contact.ID] {
        var next = self
        next.use(id)
        return next.ids
    }
}

/// A chat kept out of sight: the contact and the chat behind it.
struct KeptChat {
    let contact: Contact
    let thread: ChatThread
}

/// One chat's transcript in `ThreadPane`, shown or kept out of sight. Equal while what it shows
/// is: `jumped` is a new closure on every update of the pane, and comparing it would build every
/// kept transcript again each time.
struct KeptTranscript: View, @MainActor Equatable {
    let chat: KeptChat
    let shown: Bool
    let jump: MessageJump?
    let actions: MessageActions
    let editing: TranscriptItem.ID?
    let jumped: () -> Void

    var body: some View {
        TranscriptView(thread: chat.thread, agentName: chat.contact.name, jump: jump, jumped: jumped)
            // Not built again as it's shown or hidden: only what's below it hears that.
            .equatable()
            .environment(\.sentImages, chat.thread.sentImages)
            .environment(\.mediaProfile, chat.contact.details?.profile ?? chat.contact.id)
            .environment(\.chatContact, chat.contact)
            .environment(\.messageActions, actions)
            .environment(\.editingFrom, editing)
            .keptOutOfSight(!shown)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chat.contact == rhs.chat.contact && lhs.chat.thread === rhs.chat.thread && lhs.shown == rhs.shown
            && lhs.jump == rhs.jump && lhs.actions == rhs.actions && lhs.editing == rhs.editing
    }
}

extension View {
    /// A kept transcript you aren't looking at: still laid out, so it shows at once, but not drawn,
    /// clicked, read by VoiceOver or acting for the chat on screen.
    func keptOutOfSight(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
            .zIndex(hidden ? 0 : 1)
            .environment(\.conversationShown, !hidden)
            // A new closure on every update of the pane: a hidden chat would redraw for nothing.
            .transformEnvironment(\.showConversationDetails) { if hidden { $0 = nil } }
    }
}

extension EnvironmentValues {
    /// `false` in a transcript kept out of sight: widgets stop, secrets typed into a card go, and
    /// what it would announce to VoiceOver stays quiet, as when you used to leave a chat.
    @Entry var conversationShown = true
}
