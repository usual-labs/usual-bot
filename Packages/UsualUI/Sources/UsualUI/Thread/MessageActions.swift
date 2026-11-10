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
    /// Quotes the words you selected in a message in your next one.
    var quote: (TranscriptItem, String) -> Void = { _, _ in }
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
}

extension EnvironmentValues {
    @Entry var messageActions: MessageActions?
    /// Quotes words selected in the message around it in the next message; `nil` where a message
    /// can't be replied to.
    @Entry var quoteSelection: ((String) -> Void)?
}

/// The quick reactions, as in Messages and Grok Bot, and the rest behind + (or More Reactions).
private let quickReactions = ["👍", "👎", "❤️", "😂", "🎉"]
private let moreReactions = [
    "🙏", "👀", "🔥", "✅", "💯", "🤔", "😮", "😢", "👏", "🚀", "💡", "⚠️", "🙌", "😅", "🤝", "⭐️", "🧐", "❌",
]

/// A message in a transcript with its actions: a bar on hover and a right-click menu (Mac), a
/// long-press menu (iPhone), VoiceOver actions on both, and its reactions underneath.
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
    @ViewBuilder let content: Content

    @Environment(\.messageActions) private var actions
    @Environment(\.selectText) private var selectText
    @Environment(\.chatContact) private var chatContact
    /// The pointer is over the message, or left it a moment ago (on its way to the bar).
    @State private var overMessage = false
    @State private var overBar = false
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorScheme) private var colorScheme
    @State private var leaving: Task<Void, Never>?
    @State private var picking = false

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
            let slot: CGFloat = actions == nil ? 0 : Self.barWidth + 6
            message
                // Only the message itself shows the bar, not the empty row around it.
                .contentShape(Rectangle())
                .background { PointerTracking(changed: hoverMessage) }
                .contextMenu { if let actions { menu(actions) } }
                .padding(isMine ? .leading : .trailing, slot)
                .overlay(alignment: isMine ? .leading : .trailing) { barSlot }
                .padding(isMine ? .leading : .trailing, isMine ? 70 : 6)
                .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        #else
            message
                // Your bubbles leave the agent's side clear, as in any messenger.
                .padding(.leading, isMine ? 48 : 0)
                .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
                .contextMenu { if let actions { menu(actions) } }
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
                .environment(\.quoteSelection, actions.map { actions in { actions.quote(item, $0) } })
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
        private static var barWidth: CGFloat { 164 }

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
                .frame(width: Self.barWidth, height: 28, alignment: isMine ? .trailing : .leading)
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
                    rewindButtons(actions)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
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
                Image(systemName: systemImage).frame(width: 28, height: 28)
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

    // MARK: The right-click (Mac) and long-press (iPhone) menu

    @ViewBuilder private func menu(_ actions: MessageActions) -> some View {
        if canReact(actions) {
            #if os(macOS)
                // A Mac menu's palette leaves out buttons without an image, so emoji go in a submenu.
                Menu("React", systemImage: reactSymbol) {
                    ForEach(quickReactions, id: \.self) { emoji in
                        Button(emoji) { actions.react(emoji, item) }
                    }
                    Divider()
                    Button("More Reactions…") { picking = true }
                }
            #else
                ControlGroup {
                    ForEach(quickReactions, id: \.self) { emoji in
                        Button(emoji) { actions.react(emoji, item) }
                    }
                    Button("More Reactions", systemImage: "plus") { picking = true }
                }
                .controlGroupStyle(.palette)
            #endif
        }
        Button("Reply", systemImage: "arrowshape.turn.up.left") { actions.reply(item) }
        Button("Copy", systemImage: "doc.on.doc", action: copy)
        // Only iPhone provides this: the Mac selects within the message itself.
        if let selectText, !text.isEmpty {
            Button("Select Text", systemImage: "selection.pin.in.out") {
                selectText(SelectableText.plain(text)) { actions.quote(item, $0) }
            }
        }
        rewindButtons(actions)
        #if os(iOS)
            if let date = item.date {
                Section { Text(date.formatted(date: .abbreviated, time: .shortened)) }
            }
        #endif
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
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: Self.size, height: Self.size)
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
            Text(emoji).font(.system(size: 22)).frame(width: Self.size, height: Self.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.clickable(.borderless))
        .accessibilityLabel(Text("React \(emoji)"))
    }
}
