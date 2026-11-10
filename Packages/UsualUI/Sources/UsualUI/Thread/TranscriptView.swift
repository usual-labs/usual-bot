import HermesKit
import SwiftUI

/// The scrolling conversation: bubbles for you and the agent, tool calls folded into one line each,
/// and system notices centred.
struct TranscriptView: View {
    let thread: ChatThread
    let agentName: String
    var jump: MessageJump? = nil
    var jumped: () -> Void = {}
    /// The last item there was when the waiting cards appeared; `-1` for none, `nil` with no cards.
    @State private var cardsAfter: Int?
    @State private var window = TranscriptWindow()
    /// A message a search jumped to, kept in what's shown.
    @State private var target: Int?
    @AppStorage(AppPreferences.streamRepliesKey) private var streamsReplies = true

    var body: some View {
        // A reloaded transcript numbers its items afresh, so a position kept by item would now
        // point at an older message: start over at the newest one.
        ConversationScroll(
            reload: thread.transcriptLoad, arrival: arrival,
            sent: SentMessages(load: thread.transcriptLoad, count: thread.state.items.count(where: \.isYours)),
            jump: jump, jumped: jumped,
            earlier: { window.showEarlier(in: items, including: target) }
        ) {
            if let banner = thread.banner {
                NoticeLine(text: banner)
            }
            if thread.state.items.isEmpty, !thread.state.isRunning {
                NoticeLine(text: String(localized: "Say hello to \(agentName)."))
                    .padding(.top, 40)
            }
            let items = thread.state.items
            let dates = DateLabels.labels(for: items)
            // One ForEach, so an item or card keeps its view (and what you typed in a card) as the
            // cards move.
            let start = window.start(in: items, including: target)
            ForEach(Self.rows(of: items, cardsAt: cardsIndex, from: start), id: \.id) { row in
                switch row {
                case .item(let index, _): self.row(items[index], at: index, in: items, dates: dates)
                case .live: live
                case .cards: cards
                }
            }
        }
        .onChange(of: thread.transcriptLoad, initial: true) { window.reset(items) }
        .onChange(of: items.isEmpty) { window.reset(items) }
        .onChange(of: jump, initial: true) { if let jump { target = jump.itemID } }
        .onChange(of: hasCards, initial: true) { cardsAfter = hasCards ? items.last?.id ?? -1 : nil }
        .onChange(of: thread.transcriptLoad) { if hasCards { cardsAfter = items.last?.id ?? -1 } }
        // A card may be out of sight, or VoiceOver elsewhere in the chat.
        .onChange(of: waiting) { old, new in
            if let text = TranscriptAnnouncement.appeared(from: old, to: new, agent: agentName) {
                TranscriptAnnouncement.post(text)
            }
        }
    }

    private var items: [TranscriptItem] { thread.state.items }
    /// The reply being written, as far as the chat shows it.
    private var draft: String { streamsReplies ? thread.state.draft : "" }
    private var cardsIndex: Int { Self.cardsIndex(in: items, after: cardsAfter) }

    /// A part of the transcript: an item, the reply being written with what the turn is doing, or
    /// the cards waiting for you.
    enum Row: Equatable {
        case item(index: Int, id: Int)
        case live
        case cards

        /// An item's ID, not its index, which shifts when one is inserted earlier. Item IDs start at 0.
        var id: Int {
            switch self {
            case .item(_, let id): id
            case .live: -1
            case .cards: -2
            }
        }
    }

    /// The items from `start` in order with the cards at `split`. What's live follows the newest
    /// message, so it sits above cards nothing has followed yet. The cards show wherever they sit.
    nonisolated static func rows(of items: [TranscriptItem], cardsAt split: Int, from start: Int = 0) -> [Row] {
        let rows = items.indices.map { Row.item(index: $0, id: items[$0].id) }
        let tail: [Row] = split < items.count ? [.cards] + rows[split...] + [.live] : [.live, .cards]
        return (Array(rows[..<split]) + tail).filter {
            if case .item(let index, _) = $0 { index >= start } else { true }
        }
    }

    @ViewBuilder private func row(
        _ item: TranscriptItem, at index: Int, in items: [TranscriptItem], dates: [Int: String]
    ) -> some View {
        if let date = dates[item.id] { DateLabel(text: date) }
        // A date between two replies parts them.
        let isLast = index + 1 == items.count
        let shown = Self.shown(items, at: index)
        ItemView(
            item: shown, agentName: agentName,
            joinsAbove: item.isReply && index > 0 && items[index - 1].isReply && dates[item.id] == nil,
            joinsBelow: item.isReply
                && (isLast
                    ? !draft.isEmpty
                    : items[index + 1].isReply && dates[items[index + 1].id] == nil),
            spokenTexts: Self.spokenTexts(of: shown, in: items, at: index),
            working: isLast ? working : nil
        )
        .transition(item.arrival(streamed: streamsReplies))
        .accessibilityElement(children: .contain)
    }

    /// The reply being written and what the turn is doing, after the newest message.
    @ViewBuilder private var live: some View {
        if !draft.isEmpty {
            // Becomes a transcript item when it ends, so it leaves without a fade.
            AgentBubble(joinsAbove: items.last?.isReply == true) {
                MarkdownView(draft, isBeingWritten: true)
            }
            .joined(items.last?.isReply == true)
            .transition(.asymmetric(insertion: .settle, removal: .identity))
        }
        LiveCards(live: thread.state.live)
        if let working, !lastItemIsActivity {
            WorkingRow(text: working).transition(.settle)
        }
    }

    /// What the agent is doing, shown in one row: the newest tool line, or a row of its own after
    /// the rest. One row that changes its words, so the chat doesn't grow a row and lose it again
    /// with each tool. `nil` while a reply is shown being written, or while the agent waits for you.
    private var working: String? {
        // A card with nothing after it is what the agent waits for, so it isn't thinking. Once you
        // write after the card, the agent is working on that.
        guard draft.isEmpty, thread.state.isRunning, !hasCards || cardsIndex < items.count else { return nil }
        return WorkingRow.text(for: thread.state)
    }

    /// What the agent waits on you for.
    private var waiting: WaitingCards {
        WaitingCards(
            approvals: thread.approvals.count, questions: thread.questions.count, secrets: thread.secrets.count,
            vault: thread.vaultPrompts.count, connections: thread.connection == nil ? 0 : 1)
    }
    private var hasCards: Bool { waiting != WaitingCards() }

    /// Where the waiting cards sit: after the items there were when they appeared, so a message you
    /// send while one waits, and the answer, come after it like any other message.
    nonisolated static func cardsIndex(in items: [TranscriptItem], after anchor: Int?) -> Int {
        guard let anchor else { return items.count }
        // Undo can remove the anchor itself; an item from another device can land before it.
        return items.lastIndex { $0.id <= anchor }.map { $0 + 1 } ?? 0
    }

    @ViewBuilder private var cards: some View {
        VaultCards(thread: thread, agentName: agentName).transition(.settle)
        if let card = thread.connection {
            ConnectCard(thread: thread, card: card, agentName: agentName).transition(.settle)
        }
        ForEach(thread.approvals) { approval in
            ApprovalCard(approval: approval, agentName: agentName) { thread.answer(approval, with: $0) }
                .transition(.settle)
        }
        ForEach(thread.questions) { prompt in
            QuestionCard(
                prompt: prompt, agentName: agentName, answer: { thread.answer(prompt, with: $0) },
                skip: { thread.skip(prompt) },
                answersFromBox: thread.questionTheBoxAnswers?.id == prompt.id
            )
            .transition(.settle)
        }
        ForEach(thread.secrets) { prompt in
            SecretCard(
                prompt: prompt, agentName: agentName, isUnencrypted: thread.isLinkUnencrypted,
                answer: { thread.answer(prompt, with: $0) }, skip: { thread.skip(prompt) }
            )
            .transition(.settle)
        }
    }

    /// Changes when something arrives at the end of the conversation.
    private var arrival: [Int] {
        [
            thread.state.items.count, draft.isEmpty ? 0 : 1, thread.state.isRunning ? 1 : 0,
            thread.vaultPrompts.count, thread.approvals.count, thread.questions.count, thread.secrets.count,
            thread.connection == nil ? 0 : 1,
            thread.state.live.todos.isEmpty ? 0 : 1, thread.state.live.helpers.isEmpty ? 0 : 1,
        ]
    }

    /// The item as the chat shows it: a reply with its turn's voice files attached
    /// (`SpokenAudio.delivered`).
    nonisolated static func shown(_ items: [TranscriptItem], at index: Int) -> TranscriptItem {
        guard case .assistant(let text) = items[index].content else { return items[index] }
        var item = items[index]
        item.content = .assistant(SpokenAudio.delivered(text, in: items, replyAt: index))
        return item
    }

    /// The voice memo transcripts for a reply's audio; empty for the rest.
    nonisolated static func spokenTexts(in items: [TranscriptItem], at index: Int) -> [String: String] {
        spokenTexts(of: shown(items, at: index), in: items, at: index)
    }

    /// `spokenTexts(in:at:)` for the item as already `shown`.
    nonisolated static func spokenTexts(
        of shown: TranscriptItem, in items: [TranscriptItem], at index: Int
    ) -> [String: String] {
        guard case .assistant(let text) = shown.content, text.contains("MEDIA:") else { return [:] }
        let audio = MarkdownBlock.parse(text).compactMap { block -> String? in
            guard case .media(let path, _) = block, MediaLoading.kind(of: path) == .audio else { return nil }
            return path
        }
        return SpokenAudio.transcripts(in: items, replyAt: index, audioPaths: audio)
    }

    private var lastItemIsActivity: Bool {
        if case .activity = thread.state.items.last?.content { true } else { false }
    }
}

/// Who wrote a room reply: the name and the agent contact behind the avatar.
struct MemberAuthor {
    let name: String
    let contact: Contact
}

extension TranscriptItem {
    /// An agent's message, which joins up with those beside it.
    fileprivate var isReply: Bool {
        if case .assistant = content { true } else { false }
    }

    /// A message you wrote.
    var isYours: Bool {
        if case .user = content { true } else { false }
    }

    /// How the item comes in. A streamed reply was on screen as a draft, so it swaps in without
    /// a move.
    fileprivate func arrival(streamed: Bool) -> AnyTransition {
        switch content {
        case .user: .rise
        case .assistant: streamed ? .identity : .settle
        // The running turn's lines, kept where they were.
        case .progress: .identity
        default: .settle
        }
    }
}

extension View {
    /// Closes most of the gap to the message above, when it's from the same agent.
    fileprivate func joined(_ isJoined: Bool) -> some View {
        padding(.top, isJoined ? -8 : 0)
    }
}

struct ItemView: View {
    let item: TranscriptItem
    let agentName: String
    var joinsAbove = false
    var joinsBelow = false
    /// Transcripts for a reply's voice memos, by path.
    var spokenTexts: [String: String] = [:]
    /// What the agent is doing now, for the newest tool line to say.
    var working: String? = nil
    /// Rooms only: resolves a member ID to its author.
    var author: (String) -> MemberAuthor? = { _ in nil }
    @Environment(\.highlightedItem) private var highlighted

    var body: some View {
        content
            // Behind the row, not over it: a reply runs the column's full width.
            .background {
                if highlighted == item.id {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.foundFill)
                        .strokeBorder(Theme.foundBorder, lineWidth: 2)
                        .padding(-6)
                        .transition(.opacity)
                }
            }
            .onChange(of: highlighted == item.id, initial: true) { _, found in
                if found { TranscriptAnnouncement.post(TranscriptAnnouncement.found(item)) }
            }
    }

    @ViewBuilder private var content: some View {
        switch item.content {
        case .user(let text):
            MessageRow(
                item: item, text: QuotedMessage.split(AttachmentRef.split(text).text).text,
                author: String(localized: "You"), agentName: agentName, isMine: true
            ) {
                UserBubbleContent(text: text)
            }
        case .assistant(let text):
            MessageRow(item: item, text: text, author: agentName, agentName: agentName, isMine: false) {
                AgentBubble(joinsAbove: joinsAbove, joinsBelow: joinsBelow) { MarkdownView(text) }
                    .environment(\.spokenTexts, spokenTexts)
            }
            .joined(joinsAbove)
        case .member(let id, let text):
            let author = author(id)
            MessageRow(item: item, text: text, author: author?.name ?? id, agentName: agentName, isMine: false) {
                HStack(alignment: .top, spacing: 10) {
                    if let author {
                        AgentAvatar(contact: author.contact, size: 28)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(author?.name ?? id)
                            .scaledFont(size: 12.5, weight: .semibold)
                            .foregroundStyle(Theme.secondaryInk)
                        AgentBubble {
                            MarkdownView(text)
                                // Files a member names live in its own profile.
                                .environment(
                                    \.mediaProfile, author.map { $0.contact.details?.profile ?? $0.contact.id })
                        }
                    }
                }
            }
        case .activity(let steps):
            ActivityLine(steps: steps, agentName: agentName, working: working)
        case .progress(let todos, let helpers):
            VStack(alignment: .leading, spacing: 12) { ProgressLines(todos: todos, helpers: helpers) }
        case .notice(let text):
            NoticeLine(text: text)
        case .result(let title, let detail):
            ResultLine(title: title, detail: detail)
        case .output(let text):
            MessageRow(item: item, text: text, author: agentName, agentName: agentName, isMine: false) {
                CommandOutput(text: text)
            }
        case .background(let task, let result):
            MessageRow(item: item, text: result, author: agentName, agentName: agentName, isMine: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Background task: \(task)").lineLimit(2)
                    } icon: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .scaledFont(size: 12.5, weight: .medium)
                    .foregroundStyle(Theme.secondaryInk)
                    AgentBubble { MarkdownView(result) }
                }
            }
        }
    }
}

/// Your message on the right of the conversation.
struct UserBubble: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 64)
            UserBubbleContent(text: text)
        }
    }
}

/// Your message as wide as its text: attachments above the bubble, a quoted reply inside it.
struct UserBubbleContent: View {
    let text: String
    @Environment(\.sentImages) private var sentImages
    @Environment(\.messageTextSize) private var messageSize
    @Environment(\.chatContact) private var contact

    var body: some View {
        // Attachments travel as `@image:`/`@file:` lines after the text; they show above it.
        let (withQuote, attachments) = AttachmentRef.split(text)
        let (quotes, body) = QuotedMessage.split(withQuote)
        // Audio and video you sent get a player; the rest show as tiles.
        let (playable, tiles) = (
            attachments.filter { $0.kind == .file && MediaLoading.kind(of: $0.path).isPlayable },
            attachments.filter { $0.kind != .file || !MediaLoading.kind(of: $0.path).isPlayable }
        )
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(playable, id: \.path) { ref in
                MediaView(path: ref.path)
                    .padding(10)
                    .frame(maxWidth: 440)
                    .background(Theme.selection, in: RoundedRectangle(cornerRadius: 18))
            }
            if !tiles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tiles, id: \.path) { ref in
                        AttachmentTile(
                            kind: ref.kind, name: ref.name, imageData: sentImages[ref.path], gatewayPath: ref.path)
                    }
                }
            }
            if !body.isEmpty || !quotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // What this one replies to.
                    ForEach(Array(quotes.enumerated()), id: \.offset) { _, quote in
                        Text(quote)
                            .scaledFont(size: 13)
                            .foregroundStyle(Theme.userBubbleInk.opacity(0.7))
                            .lineLimit(2)
                            .padding(.leading, 9)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.userBubbleInk.opacity(0.35)).frame(width: 2)
                            }
                    }
                    if !body.isEmpty {
                        #if os(macOS)
                            MessageText(content: .mine(body, size: messageSize))
                        #else
                            // Links underlined in the bubble's own ink: the link colour wouldn't
                            // read on the Bot's colour.
                            Text(Links.detect(in: body).underliningLinks())
                                .messageFont()
                                .tint(Theme.userBubbleInk)
                        #endif
                    }
                }
                .foregroundStyle(Theme.userBubbleInk)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.bubblePadding)
                .padding(.vertical, 9)
                .background(contact?.accent ?? Theme.userBubble, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

struct NoticeLine: View {
    let text: String

    var body: some View {
        Text(text)
            .scaledFont(size: 13)
            .foregroundStyle(Theme.secondaryInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// One quiet line for a run of tool calls, or what's happening now; click to see each step.
private struct ActivityLine: View {
    let steps: [ToolStep]
    let agentName: String
    var working: String? = nil

    var body: some View {
        FoldedRow {
            if let now = ActivitySummary.current(in: steps) ?? working {
                WorkingRow(text: now)
            } else {
                Text(ActivitySummary.line(for: steps, agent: agentName))
                    .padding(.leading, 12)
            }
        } rows: {
            ForEach(steps) { step in
                StepRow(step: step)
            }
        }
    }
}

private struct StepRow: View {
    let step: ToolStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(ActivitySummary.verb(for: step.name))
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 52, alignment: .leading)
            Text(step.context.isEmpty ? step.name : step.context)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch step.state {
            case .running:
                ProgressView().controlSize(.mini)
            case .failed:
                Text("failed").foregroundStyle(Theme.danger)
            case .done:
                if let detail = step.summary ?? step.duration.map(ActivitySummary.duration) {
                    Text(detail).foregroundStyle(Theme.secondaryInk).lineLimit(1)
                }
            }
        }
        .scaledFont(size: 12.5, design: .monospaced)
    }
}

/// What a Hermes command printed: terminal text, so monospaced and never wrapped (its columns
/// line up); wide output scrolls sideways.
struct CommandOutput: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .scaledFont(size: 12.5, design: .monospaced)
                .foregroundStyle(Theme.ink)
                .fixedSize()
                .textSelection(.enabled)
                .padding(12)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.selection.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
