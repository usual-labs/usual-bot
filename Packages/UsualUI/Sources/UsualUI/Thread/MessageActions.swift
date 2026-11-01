import HermesKit
import SwiftUI

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// A message you're replying to: shown above the message box, then sent as a `>` quote line
/// before your text. In a room the reply also @mentions the author, so only it answers.
struct QuotedMessage: Equatable {
    let author: String
    let excerpt: String
    /// The room member to address; `nil` in a chat with one agent.
    var mention: String?

    init(author: String, text: String, mention: String? = nil) {
        self.author = author
        self.mention = mention
        // Plain words: no attachment or `MEDIA:` lines, no Markdown marks.
        let lines = AttachmentRef.split(text).text.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("MEDIA:") }
        let joined = lines.joined(separator: " ")
        let flat =
            (try? AttributedString(
                markdown: joined, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            .map { String($0.characters) } ?? joined
        excerpt = flat.count > 200 ? String(flat.prefix(200)) + "…" : flat
    }

    /// Your message with the quote in front.
    func message(_ text: String) -> String {
        let reply = [mention.map { "@\($0)" }, text.isEmpty ? nil : text].compactMap(\.self).joined(separator: " ")
        return "> \(author): \(excerpt)\n\n\(reply)"
    }

    /// Splits a leading quote off a sent message: the `> ` lines, and the rest.
    static func split(_ text: String) -> (quote: String?, text: String) {
        var lines = text.components(separatedBy: "\n")
        var quoted: [String] = []
        while let first = lines.first, first.hasPrefix("> ") {
            quoted.append(String(first.dropFirst(2)))
            lines.removeFirst()
        }
        guard !quoted.isEmpty else { return (nil, text) }
        return (
            quoted.joined(separator: " "), lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

/// What you can do to a message. Set by the chat or room; reactions exist only in chats with one
/// agent (rooms have no reaction call).
struct MessageActions {
    var canReact: (TranscriptItem) -> Bool = { _ in false }
    var react: (String?, TranscriptItem) -> Void = { _, _ in }
    var reply: (TranscriptItem) -> Void = { _ in }
    /// Chats only: your last message, between replies, can be edited or taken back.
    var canRewind: (TranscriptItem) -> Bool = { _ in false }
    var edit: (TranscriptItem) -> Void = { _ in }
    var undo: (TranscriptItem) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var messageActions: MessageActions?
}

/// The quick reactions, as in Messages and Grok Bot, and more behind +.
private let quickReactions = ["👍", "👎", "❤️", "😂", "🎉"]
private let moreReactions = [
    "🙏", "👀", "🔥", "✅", "💯", "🤔", "😮", "😢", "👏", "🚀", "💡", "⚠️", "🙌", "😅", "🤝", "⭐️", "🧐", "❌",
]

/// A message in a transcript with its actions: a bar on hover (Mac), a long-press menu (iPhone),
/// and its reactions underneath.
struct MessageRow<Content: View>: View {
    let item: TranscriptItem
    /// The text Copy takes.
    let text: String
    /// Your own messages sit on the right, so their reactions do too.
    let isMine: Bool
    @ViewBuilder let content: Content

    @Environment(\.messageActions) private var actions
    /// The pointer is over the message, or left it a moment ago (on its way to the bar).
    @State private var overMessage = false
    @State private var overBar = false
    @State private var leaving: Task<Void, Never>?
    @State private var picking = false

    var body: some View {
        #if os(macOS)
            // As in Grok Bot, the bar sits beside the message: right of a reply, left of your
            // bubble. Its slot is always there, so nothing moves when it appears.
            HStack(alignment: .center, spacing: 6) {
                if isMine {
                    Spacer(minLength: 64)
                    barSlot
                }
                // Only the message itself shows the bar, not the empty row around it.
                message
                    .contentShape(Rectangle())
                    .onHover(perform: hoverMessage)
                if !isMine {
                    barSlot
                    Spacer(minLength: 0)
                }
            }
        #else
            message
                // Your bubbles leave the agent's side clear, as in any messenger.
                .padding(.leading, isMine ? 48 : 0)
                .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
                .contextMenu { if let actions { menu(actions) } }
        #endif
    }

    private var message: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            content
            if !item.reactions.isEmpty { reactionPills }
        }
    }

    private func canReact(_ actions: MessageActions) -> Bool { actions.canReact(item) }

    // MARK: Reactions under the message

    private var reactionPills: some View {
        HStack(spacing: 4) {
            ForEach(Array(item.reactions.enumerated()), id: \.offset) { _, reaction in
                Button {
                    actions?.react(reaction.emoji, item)
                } label: {
                    Text(reaction.emoji)
                        .font(.system(size: 14))
                        .padding(.horizontal, 7)
                        .frame(minHeight: 26)
                        .background(Theme.selection, in: Capsule())
                        .overlay {
                            if !reaction.byAgent { Capsule().strokeBorder(Theme.ink.opacity(0.25)) }
                        }
                }
                .buttonStyle(.plain)
                .disabled(actions.map { !$0.canReact(item) } ?? true)
                .help(reaction.byAgent ? String(localized: "From the agent") : String(localized: "Your reaction"))
                .accessibilityLabel(
                    Text(reaction.byAgent ? "Agent reacted \(reaction.emoji)" : "You reacted \(reaction.emoji)"))
            }
        }
    }

    // MARK: Mac: the hover bar

    #if os(macOS)
        @ViewBuilder private var barSlot: some View {
            if let actions {
                let shown = overMessage || overBar || picking
                bar(actions)
                    .onHover { overBar = $0 }
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: shown)
                    .allowsHitTesting(shown)
                    // Room for all three buttons, so every reply wraps at the same width.
                    .frame(width: 104, alignment: isMine ? .trailing : .leading)
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

        private func bar(_ actions: MessageActions) -> some View {
            HStack(spacing: 2) {
                if canReact(actions) {
                    barButton("face.smiling", String(localized: "React")) { picking = true }
                        .popover(isPresented: $picking, arrowEdge: .bottom) { picker(actions) }
                }
                barButton("arrowshape.turn.up.left", String(localized: "Reply")) { actions.reply(item) }
                Menu {
                    Button("Copy", systemImage: "doc.on.doc", action: copy)
                    rewindButtons(actions)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .help("More")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.secondaryInk)
        }

        private func barButton(_ systemImage: String, _ label: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: systemImage).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(label)
            .accessibilityLabel(Text(label))
        }

        private func picker(_ actions: MessageActions) -> some View {
            ReactionPicker { emoji in
                picking = false
                actions.react(emoji, item)
            }
        }
    #endif

    // MARK: iPhone: the long-press menu

    #if os(iOS)
        @ViewBuilder private func menu(_ actions: MessageActions) -> some View {
            if canReact(actions) {
                ControlGroup {
                    ForEach(quickReactions, id: \.self) { emoji in
                        Button(emoji) { actions.react(emoji, item) }
                    }
                }
                .controlGroupStyle(.palette)
            }
            Button("Reply", systemImage: "arrowshape.turn.up.left") { actions.reply(item) }
            Button("Copy", systemImage: "doc.on.doc", action: copy)
            rewindButtons(actions)
        }
    #endif

    /// Edit and Undo, for your last message.
    @ViewBuilder private func rewindButtons(_ actions: MessageActions) -> some View {
        if actions.canRewind(item) {
            Button("Edit", systemImage: "pencil") { actions.edit(item) }
            Button("Undo", systemImage: "arrow.uturn.backward", role: .destructive) { actions.undo(item) }
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

/// Five quick reactions, and more behind +.
private struct ReactionPicker: View {
    let pick: (String) -> Void
    @State private var showsMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(quickReactions, id: \.self, content: emojiButton)
                Button {
                    showsMore.toggle()
                } label: {
                    Image(systemName: showsMore ? "chevron.up" : "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showsMore ? "Fewer" : "More reactions")
            }
            if showsMore {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 2), count: 6), spacing: 2) {
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
            Text(emoji).font(.system(size: 22)).frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("React \(emoji)"))
    }
}

/// What your message will be, above the message box: the one you're replying to, or that
/// you're editing. The button drops it.
struct ReplyChip: View {
    let text: String
    let cancelLabel: String
    let cancel: () -> Void

    init(quote: QuotedMessage, cancel: @escaping () -> Void) {
        text = "\(quote.author): \(quote.excerpt)"
        cancelLabel = String(localized: "Don't reply to \(quote.author)")
        self.cancel = cancel
    }

    init(text: String, cancelLabel: String, cancel: @escaping () -> Void) {
        self.text = text
        self.cancelLabel = cancelLabel
        self.cancel = cancel
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text(cancelLabel))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 34)
        .background(Theme.selection, in: RoundedRectangle(cornerRadius: 12))
    }
}
