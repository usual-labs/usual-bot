import HermesKit
import SwiftUI

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// What you can do to a message. Set by the chat or room; reactions exist only in chats with one
/// agent (rooms have no reaction call).
struct MessageActions {
    var canReact: (TranscriptItem) -> Bool = { _ in false }
    var react: (String?, TranscriptItem) -> Void = { _, _ in }
    var reply: (TranscriptItem) -> Void = { _ in }
    /// Quotes the words you selected in a message in your next one, with what you said to them.
    var quote: (TranscriptItem, String, String) -> Void = { _, _, _ in }
    /// Chats only: a message of yours, which can be edited.
    var canEdit: (TranscriptItem) -> Bool = { _ in false }
    /// Chats only: the Bot's last reply, which can be asked again.
    var canRetry: (TranscriptItem) -> Bool = { _ in false }
    /// Chats only: your last message, which can be taken back.
    var canRewind: (TranscriptItem) -> Bool = { _ in false }
    /// Why those can't run on this message right now; they show greyed out with it.
    var rewindUnavailable: (TranscriptItem) -> String? = { _ in nil }
    var edit: (TranscriptItem) -> Void = { _ in }
    var retry: (TranscriptItem) -> Void = { _ in }
    var undo: (TranscriptItem) -> Void = { _ in }
    /// Chats only: Mark as Unread from this message, which opening the chat again goes back to.
    /// `nil` hides it.
    var markUnread: ((TranscriptItem) -> Void)?
}

extension EnvironmentValues {
    @Entry var messageActions: MessageActions?
    /// Quotes words selected in the message around it in the next message, with your reply to
    /// them; `nil` where a message can't be replied to.
    @Entry var quoteSelection: ((_ words: String, _ reply: String) -> Void)?
}

/// The quick reactions, as in Messages and Grok Bot, and the rest behind + (or More Reactions).
let quickReactions = ["👍", "👎", "❤️", "😂", "🎉"]
let moreReactions = [
    "🙏", "👀", "🔥", "✅", "💯", "🤔", "😮", "😢", "👏", "🚀", "💡", "⚠️", "🙌", "😅", "🤝", "⭐️", "🧐", "❌",
]

/// A message in a transcript with its actions: a bar on hover and a right-click menu (Mac), a
/// touch-and-hold sheet (iPhone), VoiceOver actions on both, and its reactions underneath.
struct MessageRow<Content: View>: View {
    let item: TranscriptItem
    /// The text Copy takes.
    let text: String
    /// Who wrote it, which VoiceOver says first: "You", the agent or a room member.
    let author: String
    /// The chat's agent, who reacts to messages.
    let agentName: String
    /// Your own messages sit on the right, so their reactions do too.
    let isMine: Bool
    /// A Bot's words can be read aloud; your own messages and command output can't.
    var readsAloud = false
    /// How far the bubble starts from the row's edge: a room member's avatar sits before it.
    var bubbleInset: CGFloat = 0
    @ViewBuilder let content: Content

    @Environment(\.messageActions) private var actions
    @Environment(\.selectText) private var selectText
    @Environment(\.chatContact) private var chatContact
    @Environment(\.playbackScope) private var playbackScope
    /// The pointer is over the message, or left it a moment ago (on its way to the bar).
    @State private var overMessage = false
    @State private var overBar = false
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorScheme) private var colorScheme
    @State private var leaving: Task<Void, Never>?
    @State private var picking = false
    #if os(iOS)
        @State private var menuShown = false
        @State private var pressing = false
        /// What was picked in the menu, run once it has closed.
        @State private var afterMenu: (() -> Void)?
    #endif

    var body: some View {
        row
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(author))
    }

    @ViewBuilder private var row: some View {
        #if os(macOS)
            // As in Grok Bot, the bar sits beside the message: right of a reply, left of your
            // bubble. Its slot is always there, so nothing moves when it appears. Padding and an
            // overlay rather than a stack with a spacer: a stack measures each message several
            // ways to share out the room, which made opening a long chat slow.
            // The slot grows with the zoom, as the bar does: at a fixed width a zoomed-in bar
            // spilled over the bubble.
            let slot: CGFloat = actions == nil ? 0 : barWidth + 6
            // The whole rectangle answers a right-click, from a background: a content shape on the
            // message itself would also stop clicks on what reaches past it, as Reply over a
            // selection's first line does.
            message
                .background { Color.clear.contentShape(Rectangle()) }
                .contextMenu { if let actions { menu(actions) } }
                .padding(isMine ? .leading : .trailing, slot)
                .overlay(alignment: isMine ? .leading : .trailing) { barSlot }
                // Near the message shows the bar: its slot, hidden bar and all, and a margin on
                // the other side. Not above or below, where it would reach the next message and
                // show two bars at once.
                .background {
                    PointerTracking(changed: hoverMessage)
                        .padding(isMine ? .trailing : .leading, -Self.nearMargin)
                }
                .padding(isMine ? .leading : .trailing, isMine ? 70 : 6)
                .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        #else
            message
                .modifier(SwipeToReplyIfAble(item: item, actions: actions))
                // Your bubbles leave the agent's side clear, as in any messenger.
                .padding(.leading, isMine ? 48 : 0)
                .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
                // Pulling the conversation left shows it.
                .overlay(alignment: .trailing) { if let date = item.date { RevealedTime(date: date) } }
                .scaleEffect(pressing ? 0.97 : 1)
                .animation(.easeOut(duration: 0.2), value: pressing)
                .environment(\.selectsTextInPlace, false)
                .gesture(
                    MessageLongPress { down in
                        pressing = down && actions != nil
                    } began: {
                        if actions != nil { menuShown = true }
                    }
                )
                .sensoryFeedback(.impact(weight: .medium), trigger: menuShown) { _, shown in shown }
                .sheet(isPresented: $menuShown, onDismiss: runAfterMenu) {
                    if let actions { menuSheet(actions) }
                }
                .sheet(isPresented: $picking) {
                    if let actions {
                        picker(actions)
                            .presentationDetents([.height(280)])
                            .presentationDragIndicator(.visible)
                    }
                }
        #endif
    }

    private var message: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            content
                .environment(\.quoteSelection, actions.map { actions in { actions.quote(item, $0, $1) } })
            if isReading { stopReadingPill.padding(.leading, bubbleInset) }
            if !item.reactions.isEmpty { reactionPills }
        }
        // On each part of the message, so VoiceOver offers them wherever it lands.
        .accessibilityActions { if let actions { accessibilityActions(actions) } }
    }

    /// The menu's actions, for VoiceOver.
    @ViewBuilder private func accessibilityActions(_ actions: MessageActions) -> some View {
        if canReact(actions) { Button("React") { picking = true } }
        Button("Reply") { actions.reply(item) }
        Button("Copy", action: copy)
        if canRead { Button(readLabel, action: readAloud) }
        if actions.markUnread != nil { Button("Mark as Unread") { markUnread(actions) } }
        // VoiceOver can't grey an action out, so they're offered only while they'd run.
        if actions.rewindUnavailable(item) == nil {
            if actions.canEdit(item) { Button("Edit") { actions.edit(item) } }
            if actions.canRetry(item) { Button("Try Again") { actions.retry(item) } }
            if actions.canRewind(item) { Button("Undo") { actions.undo(item) } }
        }
    }

    private func canReact(_ actions: MessageActions) -> Bool { actions.canReact(item) }

    /// An outlined face. macOS 26 swaps the face symbols with the appearance: `face.smiling` is
    /// filled in dark mode, and `.inverse` is the outline there.
    private var reactSymbol: String { colorScheme == .dark ? "face.smiling.inverse" : "face.smiling" }

    // MARK: Read aloud

    private var readingKey: String {
        ReadAloud.key(scope: playbackScope, chat: chatContact?.id ?? "", item: item.id)
    }

    private var isReading: Bool { readsAloud && ReadAloud.shared.key == readingKey }

    /// Not during a call, which speaks for itself, and not a reply that's only code or a file.
    private var canRead: Bool {
        readsAloud && (isReading || (!ReadAloud.shared.inCall && SpokenReply.hasWords(in: text)))
    }

    private var readLabel: String { isReading ? String(localized: "Stop Reading") : String(localized: "Read Aloud") }

    @ViewBuilder private var readButton: some View {
        if canRead {
            Button(readLabel, systemImage: isReading ? "stop.circle" : "speaker.wave.2", action: readAloud)
        }
    }

    private func readAloud() {
        if isReading { ReadAloud.shared.stop() } else { ReadAloud.shared.read(text, key: readingKey) }
    }

    /// Under the message being read, so you can see which one it is and stop it without the menu.
    private var stopReadingPill: some View {
        Button(action: readAloud) {
            Label("Stop Reading", systemImage: "stop.fill").scaledFont(size: 12, weight: .medium)
        }
        .buttonStyle(.clickable(.bordered))
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(Theme.ink)
        .help("Stop reading this message aloud")
        .transition(.opacity)
    }

    // MARK: Reactions under the message

    /// System capsules; yours in the chat's colour, as your messages are.
    private var reactionPills: some View {
        HStack(spacing: 4) {
            ForEach(Array(item.reactions.enumerated()), id: \.offset) { _, reaction in
                Button {
                    actions?.react(reaction.emoji, item)
                } label: {
                    Text(reaction.emoji).scaledFont(size: 14)
                }
                .buttonStyle(.clickable(.bordered))
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(reaction.byAgent ? Theme.ink : chatContact?.accent ?? Theme.ink)
                .disabled(actions.map { !$0.canReact(item) } ?? true)
                .help(reaction.byAgent ? String(localized: "From \(agentName)") : String(localized: "Your reaction"))
                .accessibilityLabel(
                    Text(reaction.byAgent ? "\(agentName) reacted \(reaction.emoji)" : "You reacted \(reaction.emoji)"))
            }
        }
    }

    // MARK: Mac: the hover bar

    #if os(macOS)
        private static var defaultBarWidth: CGFloat { 164 }
        @Zoomed private var barWidth: CGFloat = Self.defaultBarWidth
        /// How far beside the message, away from the bar, the pointer still counts as on it.
        private static var nearMargin: CGFloat { 24 }

        @ViewBuilder private var barSlot: some View {
            if let actions {
                // A window behind others still tracks the pointer passing over it.
                let shown = picking || (appearsActive && (overMessage || overBar))
                ZStack {
                    // Made only while shown: its menu and popover for every message held up
                    // opening a long chat.
                    if shown {
                        bar(actions)
                            .onHover { overBar = $0 }
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: shown)
                // Room for all three buttons and the time, so every reply wraps at the same width.
                // A fixed size, so the bar coming and going as the pointer passes doesn't lay the
                // conversation out again.
                .zoomedFrame(width: Self.defaultBarWidth, height: 28, alignment: isMine ? .trailing : .leading)
            }
        }

        /// Leaving the message hides the bar after a moment, so the pointer can cross the gap
        /// to it; reaching the bar keeps it up.
        private func hoverMessage(_ inside: Bool) {
            leaving?.cancel()
            if inside {
                overMessage = true
            } else {
                leaving = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    if !Task.isCancelled { overMessage = false }
                }
            }
        }

        /// Bare icons, as in Grok's app: glass circles beside every message read as clutter.
        private func bar(_ actions: MessageActions) -> some View {
            HStack(spacing: 2) {
                // Grok shows when a message was sent only while you point at it.
                if isMine, let date = item.date { sentTime(date) }
                if canReact(actions) {
                    barButton(reactSymbol, String(localized: "React")) { picking = true }
                        .popover(isPresented: $picking, arrowEdge: .bottom) { picker(actions) }
                }
                barButton("arrowshape.turn.up.left", String(localized: "Reply")) { actions.reply(item) }
                Menu {
                    Button("Copy", systemImage: "doc.on.doc", action: copy)
                    readButton
                    markUnreadButton(actions)
                    rewindButtons(actions)
                } label: {
                    Image(systemName: "ellipsis").zoomedFrame(width: 28, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(.bare)
                .clickable()
                .menuIndicator(.hidden)
                .help("More")
                if !isMine, let date = item.date { sentTime(date) }
            }
            .scaledFont(size: 13, weight: .medium)
            .foregroundStyle(Theme.secondaryInk)
        }

        private func sentTime(_ date: Date) -> some View {
            Text(DateLabels.time(of: date))
                .scaledFont(size: 11.5)
                .foregroundStyle(Theme.secondaryInk)
                .monospacedDigit()
                .fixedSize()
                .padding(.horizontal, 4)
                .help(date.formatted(date: .complete, time: .shortened))
        }

        private func barButton(_ systemImage: String, _ label: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: systemImage).zoomedFrame(width: 28, height: 28)
            }
            .buttonStyle(.bare)
            .help(label)
            .accessibilityLabel(Text(label))
        }

    #endif

    /// Every reaction: in a popover from the bar on the Mac, a sheet on iPhone.
    private func picker(_ actions: MessageActions) -> some View {
        #if os(macOS)
            let showsAll = false
        #else
            let showsAll = true
        #endif
        return ReactionPicker(showsAll: showsAll) { emoji in
            picking = false
            actions.react(emoji, item)
        }
    }

    // MARK: The right-click menu (Mac) and the touch-and-hold sheet (iPhone)

    #if os(macOS)
        @ViewBuilder private func menu(_ actions: MessageActions) -> some View {
            if canReact(actions) {
                // A row of emoji across the top, as in Grok Bot. A Mac menu's palette leaves out
                // buttons without an image, so each emoji is drawn into one.
                ControlGroup {
                    ForEach(quickReactions, id: \.self) { emoji in
                        Button {
                            actions.react(emoji, item)
                        } label: {
                            Label {
                                Text("React \(emoji)")
                            } icon: {
                                emojiImage(emoji)
                            }
                        }
                    }
                    Button("More Reactions…", systemImage: "face.smiling") { picking = true }
                }
                .controlGroupStyle(.palette)
                Divider()
            }
            Button("Reply", systemImage: "arrowshape.turn.up.left") { actions.reply(item) }
            Button("Copy", systemImage: "doc.on.doc", action: copy)
            readButton
            markUnreadButton(actions)
            rewindButtons(actions)
        }

        /// An emoji as an image, for a menu palette.
        private func emojiImage(_ emoji: String) -> Image {
            let font = NSFont.systemFont(ofSize: 17)
            let string = NSAttributedString(string: emoji, attributes: [.font: font])
            let size = string.size()
            let image = NSImage(size: size, flipped: false) { rect in
                string.draw(in: rect)
                return true
            }
            return Image(nsImage: image)
        }
    #endif

    #if os(iOS)
        /// The touch-and-hold menu: reactions, then Reply and Mark as Unread, as Grok groups them;
        /// Copy, Select Text and Read Aloud; then Edit, Try Again and Undo.
        private func menuSheet(_ actions: MessageActions) -> some View {
            var words: [MessageMenuItem] = [
                MessageMenuItem(title: Text("Copy"), systemImage: "doc.on.doc", action: copy)
            ]
            // The Mac selects within the message itself; iPhone shows its words in a sheet.
            if let selectText, !text.isEmpty {
                words.append(
                    MessageMenuItem(title: Text("Select Text"), systemImage: "selection.pin.in.out") {
                        selectText(SelectableText.plain(text)) { actions.quote(item, $0, $1) }
                    })
            }
            if canRead {
                words.append(
                    MessageMenuItem(
                        title: Text(readLabel), systemImage: isReading ? "stop.circle" : "speaker.wave.2",
                        action: readAloud))
            }
            let reason = actions.rewindUnavailable(item)
            var rewind: [MessageMenuItem] = []
            if actions.canEdit(item) {
                rewind.append(
                    MessageMenuItem(title: Text("Edit"), systemImage: "pencil", isDisabled: reason != nil) {
                        actions.edit(item)
                    })
            }
            if actions.canRetry(item) {
                rewind.append(
                    MessageMenuItem(title: Text("Try Again"), systemImage: "arrow.clockwise", isDisabled: reason != nil)
                    {
                        actions.retry(item)
                    })
            }
            if actions.canRewind(item) {
                rewind.append(
                    MessageMenuItem(
                        title: Text("Undo"), systemImage: "arrow.uturn.backward", isDestructive: true,
                        isDisabled: reason != nil
                    ) { actions.undo(item) })
            }
            let reply = MessageMenuItem(title: Text("Reply"), systemImage: "arrowshape.turn.up.left") {
                actions.reply(item)
            }
            var answer = [reply]
            if actions.markUnread != nil {
                answer.append(
                    MessageMenuItem(title: Text("Mark as Unread"), systemImage: "envelope.badge") {
                        markUnread(actions)
                    })
            }
            return MessageMenuSheet(
                react: canReact(actions) ? { actions.react($0, item) } : nil,
                groups: [answer, words, rewind],
                note: rewind.isEmpty ? nil : reason,
                date: item.date
            ) { action in
                afterMenu = action
                menuShown = false
            }
        }

        private func runAfterMenu() {
            let action = afterMenu
            afterMenu = nil
            action?()
        }
    #endif

    @ViewBuilder private func markUnreadButton(_ actions: MessageActions) -> some View {
        if actions.markUnread != nil {
            Button("Mark as Unread", systemImage: "envelope.badge") { markUnread(actions) }
        }
    }

    private func markUnread(_ actions: MessageActions) {
        actions.markUnread?(item)
        AccessibilityNotification.Announcement(String(localized: "Marked as unread")).post()
    }

    /// Edit for your messages, Try Again for the Bot's last reply, Undo for your last message.
    /// Between replies and online; otherwise greyed out, with the reason under them.
    @ViewBuilder private func rewindButtons(_ actions: MessageActions) -> some View {
        let canEdit = actions.canEdit(item)
        let canRetry = actions.canRetry(item)
        let canUndo = actions.canRewind(item)
        if canEdit || canRetry || canUndo {
            let reason = actions.rewindUnavailable(item)
            Group {
                if canEdit { Button("Edit", systemImage: "pencil") { actions.edit(item) } }
                if canRetry { Button("Try Again", systemImage: "arrow.clockwise") { actions.retry(item) } }
                if canUndo {
                    Button("Undo", systemImage: "arrow.uturn.backward", role: .destructive) { actions.undo(item) }
                }
            }
            .disabled(reason != nil)
            if let reason { Text(reason) }
        }
    }

    private func copy() {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }
}

/// Five quick reactions and more behind +, or all of them at once.
private struct ReactionPicker: View {
    var showsAll = false
    let pick: (String) -> Void
    @State private var showsMore = false

    #if os(iOS)
        private static let size: CGFloat = 44
    #else
        private static let size: CGFloat = 36
    #endif

    var body: some View {
        if showsAll {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.size), spacing: 4), count: 6), spacing: 4) {
                ForEach(quickReactions + moreReactions, id: \.self, content: emojiButton)
            }
            .padding(12)
        } else {
            compact
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(quickReactions, id: \.self, content: emojiButton)
                Button {
                    showsMore.toggle()
                } label: {
                    Image(systemName: showsMore ? "chevron.up" : "plus")
                        .zoomedFont(size: 13, weight: .semibold)
                        .zoomedFrame(width: Self.size, height: Self.size)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.clickable(.borderless))
                .foregroundStyle(.secondary)
                .help(showsMore ? "Fewer" : "More reactions")
                .accessibilityLabel(Text(showsMore ? "Fewer reactions" : "More reactions"))
            }
            if showsMore {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.size), spacing: 2), count: 6), spacing: 2) {
                    ForEach(moreReactions, id: \.self, content: emojiButton)
                }
            }
        }
        .padding(6)
    }

    private func emojiButton(_ emoji: String) -> some View {
        Button {
            pick(emoji)
        } label: {
            Text(emoji).scaledFont(size: 22).zoomedFrame(width: Self.size, height: Self.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.clickable(.borderless))
        .accessibilityLabel(Text("React \(emoji)"))
    }
}
