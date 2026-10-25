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

    /// The message box's distance from the window's sides, in chats and rooms. iPhone gives the
    /// box more of its narrow width.
    #if os(iOS)
        static let composerMargin: CGFloat = 12
    #else
        static let composerMargin: CGFloat = 20
    #endif

    /// Files waiting to go with the next message.
    @State private var attachments: [Attachment] = []
    /// The message you're replying to.
    @State private var replyTo: QuotedMessage?
    /// You're rewriting your last message.
    @State private var editing = false
    @State private var calling = false
    @State private var isDropTarget = false

    var body: some View {
        content
            .environment(\.sentImages, thread?.sentImages ?? [:])
            .environment(\.mediaProfile, contact.details?.profile ?? contact.id)
            .environment(\.messageActions, actions)
            // The call bar floats under the name; the conversation scrolls on behind it.
            .safeAreaInset(edge: .top, spacing: 0) {
                if calling, let thread {
                    CallBar(contact: contact, thread: thread) { calling = false }
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: calling)
            // On the Mac the model menus under the box bring their own space, so the bar's margin
            // shrinks. iPhone shows them inside the box.
            .chatBars(bottomPadding: thread?.model == nil ? nil : ModelControls.gap) {
                namePill
            } bottom: {
                if let thread, thread.phase == .ready {
                    Composer(
                        thread: thread, agentName: contact.name, agentDefault: contact.details,
                        attachments: $attachments, replyTo: $replyTo,
                        editing: $editing,
                        inCall: calling, startCall: { calling = true }
                    )
                    .frame(maxWidth: 780)
                    // On the Mac, ModelControls' row and gaps below the box add up to this margin too.
                    .padding(.horizontal, Self.composerMargin)
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
                calling = false
                replyTo = nil
                editing = false
            }
            .paneChrome()
    }

    /// React, reply, edit and undo, for the transcript's messages.
    private var actions: MessageActions? {
        guard let thread else { return nil }
        return MessageActions(
            canReact: thread.canReact(to:), react: { thread.react($0, to: $1) },
            reply: { item in
                editing = false
                switch item.content {
                case .user(let text): replyTo = QuotedMessage(author: String(localized: "You"), text: text)
                case .assistant(let text): replyTo = QuotedMessage(author: contact.name, text: text)
                default: break
                }
            },
            canRewind: { item in thread.canRewind && item.id == thread.lastSent?.id },
            edit: { item in
                replyTo = nil
                editing = true
                thread.prefill = ChatThread.editableText(of: item)
            },
            undo: { _ in
                editing = false
                Task { await thread.undo() }
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
    /// `bottomPadding` replaces the usual margin under `bottom`.
    func chatBars(
        bottomPadding: CGFloat? = nil, @ViewBuilder top: () -> some View, @ViewBuilder bottom: () -> some View
    ) -> some View {
        modifier(ChatBars(top: top(), bottom: bottom(), bottomPadding: bottomPadding))
    }

    #if os(iOS)
        /// The pill keeps its own glass instead of sitting in the bar's shared background.
        @ViewBuilder func principalToolbarItem(_ item: some View) -> some View {
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

private struct ChatBars<Top: View, Bottom: View>: ViewModifier {
    let top: Top
    let bottom: Bottom
    /// The Mac's margin under `bottom`, in place of the usual one.
    let bottomPadding: CGFloat?
    /// Counts clicks and taps on the conversation, so the message box can close its menu.
    @State private var outsideTaps = 0
    /// iPhone: the safe area under the bottom bar, the home indicator's or the keyboard's.
    @State private var bottomInset: CGFloat = 0

    func body(content: Content) -> some View {
        let conversation = content.simultaneousGesture(TapGesture().onEnded { outsideTaps += 1 })
        let bottom = bottom.environment(\.conversationTaps, outsideTaps)
        #if os(macOS)
            // 9 pt centres the name on the line of the window buttons and the sidebar's buttons;
            // the message box sits a little further from the bottom edge.
            conversation
                .safeAreaInset(edge: .top, spacing: 0) { top.padding(.top, 9).padding(.bottom, 8) }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottom.padding(.top, 8).padding(.bottom, bottomPadding ?? 14)
                }
        #else
            conversation
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottom.padding(.top, 8).padding(.bottom, iPhoneBottomPadding)
                }
                // A view that reaches past the safe area measures it.
                .background {
                    Color.clear
                        .ignoresSafeArea(.container, edges: .bottom)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.safeAreaInsets.bottom
                        } action: {
                            bottomInset = $0
                        }
                }
                .navigationBarTitleDisplayMode(.inline)
                .principalToolbarItem(top)
        #endif
    }

    #if os(iOS)
        /// iPhone: with the keyboard down the box reaches a little into the home indicator's area, so
        /// it sits low like other messengers'; with the keyboard up it keeps clear of the keys. A home
        /// indicator takes 34 pt at most and a keyboard hundreds (see known issues); phones without a
        /// home indicator report none.
        private var iPhoneBottomPadding: CGFloat {
            if bottomInset > 50 { return 10 }
            return bottomInset > 0 ? -8 : 12
        }
    #endif
}

extension EnvironmentValues {
    /// Goes up with each click or tap on the conversation above the message box.
    @Entry var conversationTaps = 0
    /// The round buttons in the message box: 28 pt on the Mac, larger on iPhone.
    @Entry var composerButtonSize: CGFloat = 28
}
