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
    @State private var hovering = false
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
                message.frame(maxWidth: isMine ? nil : .infinity, alignment: .leading)
                if !isMine { barSlot }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        #else
            message
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
                let shown = hovering || picking
                bar(actions)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    // Room for all three buttons, so every reply wraps at the same width.
                    .frame(width: 104, alignment: isMine ? .trailing : .leading)
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
            .padding(.horizontal, 4)
            .floatingSurface(in: Capsule())
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
        }
    #endif

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

/// The message you're replying to, above the message box, with a button to drop it.
struct ReplyChip: View {
    let quote: QuotedMessage
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(quote.author): \(quote.excerpt)")
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
            .accessibilityLabel(Text("Don't reply to \(quote.author)"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 34)
        .background(Theme.selection, in: RoundedRectangle(cornerRadius: 12))
    }
}
