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
    /// A message search chose in this chat, to scroll to.
    var jump: MessageJump? = nil
    var jumped: () -> Void = {}

    /// The message box's and the conversation's distances from the window's sides, in chats and
    /// rooms. On iPhone the box reaches a little wider than the messages, so the text has room.
    #if os(iOS)
        static let composerMargin: CGFloat = 12
        static let contentMargin: CGFloat = 16
    #else
        static let composerMargin: CGFloat = 20
        static let contentMargin: CGFloat = 20
        /// The header's name and round buttons, the message box on one line, and the sidebar's
        /// footer items are all this tall, so the window's controls read as one set.
        static let barItemHeight: CGFloat = 36
        /// How far those controls keep from the window's top and bottom edges: the header's below
        /// the top, on the line of the window buttons; the message box and sidebar footer above the
        /// bottom.
        static let barEdgeMargin: CGFloat = 9
    #endif

    /// Files waiting to go with the next message.
    @State private var attachments: [Attachment] = []
    /// What your next message quotes: messages you're replying to and words you added from them.
    @State private var quotes: [QuotedMessage] = []
    /// The message of yours you're rewriting.
    @State private var editing: TranscriptItem.ID?
    /// An edit or Try Again that removes enough to ask first.
    @State private var rewindRequest: RewindRequest?
    @State private var calling = false
    @State private var isDropTarget = false
    @State private var showsComputer = false
    @State private var showsBrowser = false
    @Environment(\.screens) private var screens
    @Environment(\.gatewayOnline) private var isOnline
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        content
            .environment(\.sentImages, thread?.sentImages ?? [:])
            .environment(\.mediaProfile, contact.details?.profile ?? contact.id)
            .environment(\.messageActions, actions)
            .environment(\.editingFrom, editing)
            .rewindConfirmation($rewindRequest, agentName: contact.name) { request in
                guard let thread else { return }
                switch request.kind {
                case .edit(let item, let text):
                    editing = nil
                    Task { await thread.edit(item, to: text) }
                case .tryAgain: Task { await thread.tryAgain() }
                }
            }
            // The call bar floats under the name; the conversation scrolls on behind it, faded by
            // the scroll edge as under the bars.
            .safeAreaBar(edge: .top, spacing: 0) {
                if calling, let thread {
                    CallBar(contact: contact, thread: thread) { calling = false }
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: calling)
            .chatBars {
                namePill
            } actions: {
                browserButton
                computerButton
                #if os(iOS)
                    moreMenu
                #endif
            } bottom: {
                if let thread, thread.phase == .ready {
                    Composer(
                        thread: thread, chatID: contact.id, agentName: contact.name, agentDefault: contact.details,
                        attachments: $attachments, quotes: $quotes,
                        editing: $editing, confirm: { rewindRequest = $0 },
                        inCall: calling, startCall: { calling = true }
                    )
                    .frame(maxWidth: Theme.columnWidth)
                    // On the Mac, the context meter's row and gaps below the box add up to this margin too.
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
            #if os(iOS)
                .fullScreenCover(isPresented: $showsComputer) {
                    if let screen {
                        ScreenView(contact: contact, screen: screen, thread: thread) { showsComputer = false }
                        .environment(\.gatewayOnline, isOnline)
                    }
                }
                .fullScreenCover(isPresented: $showsBrowser) {
                    if let browser {
                        BrowserView(contact: contact, browser: browser, thread: thread) { showsBrowser = false }
                        .environment(\.gatewayOnline, isOnline)
                    }
                }
            #endif
            .environment(\.chatContact, contact)
            .task(id: contact.id) { open() }
            // Whether the agent has a computer or browser to show, asked again once the gateway is back.
            .task(id: "\(contact.id) \(isOnline)") {
                await screen?.refresh()
                await browser?.refresh()
            }
            .onChange(of: contact.id) {
                attachments = []
                calling = false
                quotes = []
                editing = nil
                rewindRequest = nil
            }
            // The message box goes while a chat reloads, and the edit in it.
            .onChange(of: thread?.phase == .ready) { _, ready in
                if !ready { editing = nil }
            }
            .paneChrome()
    }

    /// React, reply, edit, try again and undo, for the transcript's messages.
    private var actions: MessageActions? {
        guard let thread else { return nil }
        return MessageActions(
            canReact: thread.canReact(to:), react: { thread.react($0, to: $1) },
            reply: { item in
                editing = nil
                switch item.content {
                case .user(let text): quotes.add(QuotedMessage(author: String(localized: "You"), text: text))
                case .assistant(let text): quotes.add(QuotedMessage(author: contact.name, text: text))
                default: break
                }
            },
            quote: { item, selection in
                editing = nil
                switch item.content {
                case .user: quotes.add(QuotedMessage(author: String(localized: "You"), selection: selection))
                default: quotes.add(QuotedMessage(author: contact.name, selection: selection))
                }
            },
            canEdit: \.isYours,
            canRetry: { item in item.id == thread.retryReply?.id },
            canRewind: { item in item.id == thread.lastSent?.id },
            rewindUnavailable: { item in
                item.id == thread.retryReply?.id ? thread.tryAgainUnavailable : thread.rewindUnavailable
            },
            edit: { item in
                quotes = []
                editing = item.id
                thread.prefill = ChatThread.editableText(of: item)
            },
            retry: { _ in
                editing = nil
                guard let last = thread.lastSent, let cost = thread.rewindCost(of: last) else { return }
                if cost.needsConfirmation {
                    rewindRequest = RewindRequest(kind: .tryAgain, cost: cost)
                } else {
                    Task { await thread.tryAgain() }
                }
            },
            undo: { _ in
                editing = nil
                Task { await thread.undo() }
            })
    }

    /// The name opens the profile, as a contact's name does in Messages.
    @ViewBuilder private var namePill: some View {
        if let toggleProfile {
            NamePill(contact: contact, members: members, action: toggleProfile)
                .accessibilityHint(Text("Shows routines and details"))
        } else {
            NamePill(contact: contact, members: members)
        }
    }

    #if os(iOS)
        /// Grok's "…" at the chat's top right, beside the computer: the chat's other ways in. The
        /// message box has the call too, so the bar doesn't show it as a button of its own.
        private var moreMenu: some View {
            Menu("More", systemImage: "ellipsis") {
                if let toggleProfile {
                    Button("View Profile", systemImage: "person.crop.circle", action: toggleProfile)
                }
                if thread?.phase == .ready, !calling {
                    Button("Voice Call", systemImage: "waveform") { calling = true }
                }
            }
        }
    #endif

    /// The agent's computer, for agents only.
    private var screen: BotScreen? {
        contact.kind == .agent ? screens?.screen(for: contact) : nil
    }

    /// The agent's browser, for agents only.
    private var browser: BotBrowser? {
        contact.kind == .agent ? screens?.browser(for: contact) : nil
    }

    /// Opens the agent's computer: a window on the Mac, full screen on iPhone. A dot shows while the
    /// agent is using it.
    @ViewBuilder private var computerButton: some View {
        if let screen, screen.hasScreen {
            let working = thread?.state.isUsingComputer == true
            liveButton("Computer", systemImage: "display", working: working) {
                #if os(macOS)
                    openWindow(id: "bot-screen", value: contact.id)
                #else
                    showsComputer = true
                #endif
            }
            .help(working ? "\(contact.name) is using its computer" : "\(contact.name)'s computer")
            .accessibilityLabel(Text("\(contact.name)'s Computer"))
        }
    }

    /// Opens the agent's browser, for an agent that browses with your real browser profile: a window
    /// on the Mac, full screen on iPhone. A dot shows while the agent is browsing.
    @ViewBuilder private var browserButton: some View {
        if let browser, browser.isAvailable {
            let working = thread?.state.isUsingBrowser == true
            liveButton("Browser", systemImage: "globe", working: working) {
                #if os(macOS)
                    openWindow(id: "bot-browser", value: contact.id)
                #else
                    showsBrowser = true
                #endif
            }
            .help(working ? "\(contact.name) is browsing" : "\(contact.name)'s browser")
            .accessibilityLabel(Text("\(contact.name)'s Browser"))
        }
    }

    /// A round button in the chat's bar for something of the agent's you can watch live.
    private func liveButton(
        _ title: LocalizedStringKey, systemImage: String, working: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                #if os(macOS)
                    // The name capsule's glass, level with it and as tall: the system's glass
                    // button drew a pale disc in the window you're at, unlike the capsule beside it.
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: ThreadPane.barItemHeight, height: ThreadPane.barItemHeight)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
                #endif
                .overlay(alignment: .topTrailing) {
                    if working {
                        Circle().fill(Theme.online).frame(width: 9, height: 9)
                            #if os(macOS)
                                .offset(x: -1, y: 1)
                            #else
                                .offset(x: 3, y: -3)
                            #endif
                            .accessibilityHidden(true)
                    }
                }
        }
        #if os(macOS)
            .buttonStyle(.clickable)
        #endif
        .accessibilityValue(working ? Text("In use") : Text(""))
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
                        .buttonStyle(.clickable(.bordered))
                }
                .padding(.horizontal, 32)
            }
        case .ready:
            if let thread {
                // Every chat numbers its items from 0, so without this a switch would animate one
                // chat's messages into the next and carry over where you'd scrolled to.
                TranscriptView(thread: thread, agentName: contact.name, jump: jump, jumped: jumped).id(contact.id)
            }
        }
    }

    private func centred(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .scaledFont(size: 13)
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

    /// Pins `top` (the name), `actions` and `bottom` (the message box) over a conversation that
    /// scrolls beneath them. On iPhone the name and actions ride in the navigation bar, which the
    /// system draws in Liquid Glass; on the Mac they float over the conversation in glass of their
    /// own.
    func chatBars(
        @ViewBuilder top: () -> some View, @ViewBuilder actions: () -> some View = { EmptyView() },
        @ViewBuilder bottom: () -> some View
    ) -> some View {
        modifier(ChatBars(top: top(), actions: actions(), bottom: bottom()))
    }

    #if os(iOS)
        /// Content fades and blurs softly under the bars at the top and bottom, as in Grok's phone
        /// app.
        func softScrollEdges() -> some View {
            scrollEdgeEffectStyle(.soft, for: .all)
        }
    #endif
}

/// The name at the top of a chat or room, in a glass capsule: avatar and name, which opens the
/// profile or the room's details when there's an `action`. On iPhone it's the navigation bar's
/// title item.
struct NamePill: View {
    let contact: Contact
    let members: [Contact]
    var action: (() -> Void)?

    // On iPhone as tall as the bar's glass buttons beside it; on the Mac as tall as the sidebar's
    // Search and New Room, on the same line as them.
    #if os(iOS)
        private static let height: CGFloat = 44
        private static let avatar: CGFloat = 32
        private static let nameSize: CGFloat = 17
        private static let nameWeight: Font.Weight = .semibold
        private static let leading: CGFloat = 6
        private static let trailing: CGFloat = 18
    #else
        private static let height = ThreadPane.barItemHeight
        private static let avatar: CGFloat = 26
        private static let nameSize: CGFloat = 14
        private static let nameWeight: Font.Weight = .medium
        private static let leading: CGFloat = 5
        private static let trailing: CGFloat = 16
    #endif

    var body: some View {
        Group {
            if let action {
                Button(action: macAction(action)) { label }
                    #if os(iOS)
                        // The Mac's is in the View menu.
                        .keyboardShortcut("i", modifiers: .command)
                    #else
                        .buttonStyle(.clickable)
                    #endif
            } else {
                label
            }
        }
        // Sits in the navigation bar between two fixed buttons, so it grows only a little, as the
        // system's own titles do; touch and hold shows the name larger.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityAddTraits(.isHeader)
        .accessibilityShowsLargeContentViewer()
    }

    /// On the Mac a click opens or closes the side panel a moment after the button lets go. In the
    /// same update as the release, the button's pressed look turns animation off for its label, so
    /// the name jumped to its new place while the rest of the chat slid. A press from VoiceOver or
    /// accessibility never sets that state and slid either way.
    private func macAction(_ action: @escaping () -> Void) -> () -> Void {
        #if os(macOS)
            { DispatchQueue.main.async(execute: action) }
        #else
            action
        #endif
    }

    private var label: some View {
        HStack(spacing: 8) {
            switch contact.kind {
            case .agent: AgentAvatar(contact: contact, size: Self.avatar)
            case .room: RoomAvatar(members: members, size: Self.avatar)
            }
            Text(contact.name)
                .scaledFont(size: Self.nameSize, weight: Self.nameWeight)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .padding(.leading, Self.leading)
        .padding(.trailing, Self.trailing)
        .frame(height: Self.height)
        .contentShape(Capsule())
        // Liquid Glass of its own: iOS draws a bar's title item without any, and a plain name
        // was hard to read over a dark bubble scrolling under it. It answers a press as a button.
        .glassEffect(action == nil ? .regular : .regular.interactive(), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct ChatBars<Top: View, Actions: View, Bottom: View>: ViewModifier {
    let top: Top
    let actions: Actions
    let bottom: Bottom
    /// Counts clicks and taps on the conversation, so the message box can close its menu.
    @State private var outsideTaps = 0
    /// iPhone: the safe area under the bottom bar, the home indicator's or the keyboard's.
    @State private var bottomInset: CGFloat = 0
    /// iPhone: the window's own bottom safe area, the home indicator's alone (0 without one).
    @State private var homeIndicator: CGFloat = 0

    func body(content: Content) -> some View {
        let conversation = content.simultaneousGesture(TapGesture().onEnded { outsideTaps += 1 })
        let bottom = bottom.environment(\.conversationTaps, outsideTaps)
        #if os(macOS)
            // The message box sits as far from the bottom edge as the header from the top, level
            // with the sidebar's footer.
            macBars(conversation) {
                bottom.padding(.top, 8).padding(.bottom, ThreadPane.barEdgeMargin)
            }
        #else
            iPhoneBottomBar(conversation, bottom.padding(.top, 8).padding(.bottom, iPhoneBottomPadding))
                // A view that reaches past the safe area measures it.
                .background {
                    Color.clear
                        .ignoresSafeArea(.container, edges: .bottom)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.safeAreaInsets.bottom
                        } action: {
                            bottomInset = $0
                            homeIndicator = Self.windowBottomInset
                        }
                }
                .navigationBarTitleDisplayMode(.inline)
                // The system groups the actions in one glass capsule; the name brings its own.
                .toolbar {
                    ToolbarItem(placement: .principal) { top }.sharedBackgroundVisibility(.hidden)
                    ToolbarItemGroup(placement: .topBarTrailing) { actions }
                }
        #endif
    }

    #if os(macOS)
        /// The name and actions float over the conversation, which scrolls under them and under the
        /// message box. The header sits on `HeaderGlass`, as the sidebar's top does; the message
        /// box's own glass blurs at the bottom. Not window toolbar items: those centre on the window, not the chat beside
        /// the sidebar (see known issues).
        private func macBars(_ conversation: some View, @ViewBuilder bottom: () -> some View) -> some View {
            conversation
                .safeAreaBar(edge: .top, spacing: 0) {
                    top.frame(maxWidth: .infinity)
                        // In a row: an overlay alone would stack the actions on top of each other.
                        .overlay(alignment: .trailing) {
                            HStack(spacing: 8) { actions }.padding(.trailing, ThreadPane.composerMargin)
                        }
                        // Centres the name on the line of the window buttons and the sidebar's.
                        .padding(.top, ThreadPane.barEdgeMargin)
                        .padding(.bottom, 8)
                        .background { HeaderGlass(ground: Theme.pane).padding(.bottom, -HeaderGlass.fade) }
                }
                .safeAreaBar(edge: .bottom, spacing: 0, content: bottom)
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        }
    #endif

    #if os(iOS)
        /// The box is a bar the conversation scrolls under, softly blurred and faded as in Grok's
        /// phone app, and the top edge fades the same way under the name and buttons. The scrims
        /// fade it into the pane's colour behind both bars.
        private func iPhoneBottomBar(_ conversation: some View, _ bar: some View) -> some View {
            conversation
                .topEdgeScrim()
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    bar.environment(\.keyboardUp, bottomInset > homeIndicator)
                        .bottomEdgeScrim()
                }
                .softScrollEdges()
        }

        /// iPhone: with the keyboard down the box reaches a little into the home indicator's area, so
        /// it sits low like other messengers'; with the keyboard up it keeps clear of the keys. The
        /// bar's safe area counts both (see known issues), so the window's, which leaves out the
        /// keyboard, tells them apart. The margin eases between the two over the keyboard's last
        /// 20 pt: a swipe that pulls the keyboard down doesn't end in a jump.
        private var iPhoneBottomPadding: CGFloat {
            let resting: CGFloat = homeIndicator > 0 ? -8 : 12
            let keyboard = max(0, bottomInset - homeIndicator)
            return resting + (10 - resting) * min(1, keyboard / 20)
        }

        private static var windowBottomInset: CGFloat {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first }
                .first?.safeAreaInsets.bottom ?? 0
        }
    #endif
}

extension EnvironmentValues {
    /// Goes up with each click or tap on the conversation above the message box.
    @Entry var conversationTaps = 0
    /// The round buttons in the message box: 28 pt on the Mac, larger on iPhone.
    @Entry var composerButtonSize: CGFloat = 28
    /// iPhone: the keyboard is up under the message box. It changes as the keyboard starts to move,
    /// in that move's animation.
    @Entry var keyboardUp = false
}
