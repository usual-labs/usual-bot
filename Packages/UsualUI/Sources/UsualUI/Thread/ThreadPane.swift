import HermesKit
import SwiftUI

/// The chat column for one contact: the conversation runs the pane's full height, under the
/// name at the top and the message box at the bottom.
struct ThreadPane: View {
    let contact: Contact
    let members: [Contact]
    /// `nil` for contacts without a chat yet (rooms arrive in a later milestone).
    let thread: ChatThread?
    var open: () -> Void = {}
    /// Shows or hides the agent's profile; `nil` when the contact has none.
    var toggleProfile: (() -> Void)? = nil

    /// Files waiting to go with the next message.
    @State private var attachments: [Attachment] = []
    /// The message you're replying to.
    @State private var replyTo: QuotedMessage?
    @State private var isDropTarget = false

    var body: some View {
        content
            .environment(\.sentImages, thread?.sentImages ?? [:])
            .environment(\.mediaProfile, contact.details?.profile ?? contact.id)
            .environment(\.messageActions, actions)
            .chatBars {
                namePill
            } bottom: {
                if let thread, thread.phase == .ready {
                    Composer(thread: thread, agentName: contact.name, attachments: $attachments, replyTo: $replyTo)
                        .frame(maxWidth: 780)
                        .padding(.horizontal, 20)
                }
            }
            // Drop files anywhere on the chat to attach them.
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTarget) { providers in
                guard thread?.phase == .ready else { return false }
                Task { attachments.append(contentsOf: await AttachmentLoader.load(providers)) }
                return true
            }
            .overlay {
                if isDropTarget, thread?.phase == .ready {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Theme.ink.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .task(id: contact.id) { open() }
            .onChange(of: contact.id) {
                attachments = []
                replyTo = nil
            }
            .paneChrome()
    }

    /// React and reply, for the transcript's messages.
    private var actions: MessageActions? {
        guard let thread else { return nil }
        return MessageActions(
            canReact: thread.canReact(to:), react: { thread.react($0, to: $1) },
            reply: { item in
                switch item.content {
                case .user(let text): replyTo = QuotedMessage(author: String(localized: "You"), text: text)
                case .assistant(let text): replyTo = QuotedMessage(author: contact.name, text: text)
                default: break
                }
            })
    }

    @ViewBuilder private var namePill: some View {
        if let toggleProfile {
            Button(action: toggleProfile) { NamePill(contact: contact, members: members) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows routines and details"))
                .keyboardShortcut("i", modifiers: .command)
        } else {
            NamePill(contact: contact, members: members)
        }
    }

    @ViewBuilder private var content: some View {
        switch thread?.phase {
        case nil:
            centred { Text("No messages yet") }
        case .loading:
            centred { ProgressView().controlSize(.small) }
        case .failed(let message):
            centred {
                VStack(spacing: 10) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Try Again", action: open)
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 32)
            }
        case .ready:
            if let thread {
                TranscriptView(thread: thread, agentName: contact.name)
            }
        }
    }

    private func centred(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.system(size: 13))
            .foregroundStyle(Theme.secondaryInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// The chat column's look: the pane colour, filling its column.
    func paneChrome() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.pane)
            #if os(macOS)
                // The window has no title bar, so the name sits as far from the window's top edge
                // as the message box does from its bottom edge.
                .ignoresSafeArea(.container, edges: .top)
            #endif
    }

    /// Pins `top` (the name) and `bottom` (the message box) over a conversation that scrolls
    /// beneath them. On iPhone the name rides in the navigation bar, beside the back button.
    func chatBars(@ViewBuilder top: () -> some View, @ViewBuilder bottom: () -> some View) -> some View {
        #if os(macOS)
            // 9 pt centres the name on the line of the window buttons and the sidebar's buttons;
            // the message box keeps the same distance from the bottom.
            safeAreaInset(edge: .top, spacing: 0) { top().padding(.top, 9).padding(.bottom, 8) }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottom().padding(.top, 8).padding(.bottom, 9) }
        #else
            safeAreaInset(edge: .bottom, spacing: 0) { bottom().padding(.top, 8).padding(.bottom, 8) }
                .navigationBarTitleDisplayMode(.inline)
                .principalToolbarItem(top())
        #endif
    }

    #if os(iOS)
        /// The pill keeps its own glass instead of sitting in the bar's shared background.
        @ViewBuilder fileprivate func principalToolbarItem(_ item: some View) -> some View {
            if #available(iOS 26, *) {
                toolbar { ToolbarItem(placement: .principal) { item }.sharedBackgroundVisibility(.hidden) }
            } else {
                toolbar { ToolbarItem(placement: .principal) { item } }
            }
        }
    #endif
}

/// The floating, centred pill at the top of a thread: avatar and name.
struct NamePill: View {
    let contact: Contact
    let members: [Contact]

    var body: some View {
        HStack(spacing: 8) {
            switch contact.kind {
            case .agent: AgentAvatar(contact: contact, size: 26)
            case .room: RoomAvatar(members: members, size: 26)
            }
            Text(contact.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .padding(.leading, 5)
        .padding(.trailing, 16)
        // As tall as the sidebar's Search and New Room, on the same line as them.
        .frame(height: 36)
        .floatingSurface(in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
