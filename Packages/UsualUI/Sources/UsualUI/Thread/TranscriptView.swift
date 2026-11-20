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
    /// The message the chat was marked unread from on this device, gone back to on opening it.
    @State private var returnJump: MessageJump?
    @AppStorage(AppPreferences.streamRepliesKey) private var streamsReplies = true
    @AppStorage(AppPreferences.showToolActivityKey) private var showsTools = true

    var body: some View {
        // A reloaded transcript numbers its items afresh, so a position kept by item would now
        // point at an older message: start over at the newest one.
        ConversationScroll(
            reload: thread.transcriptLoad, arrival: arrival,
            sent: SentMessages(load: thread.transcriptLoad, count: thread.state.items.count(where: \.isYours)),
            jump: jump ?? returnJump,
            jumped: {
                if jump == nil { returnJump = nil } else { jumped() }
            },
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
            // A hidden line's date goes to the next line shown.
            let dates = DateLabels.labels(for: showsTools ? items : items.filter { !$0.isToolActivity })
            // One ForEach, so an item or card keeps its view (and what you typed in a card) as the
            // cards move.
            let start = window.start(in: items, including: target)
            ForEach(
                Self.rows(of: items, cardsAt: cardsIndex, from: start, folding: exchanges, showingTools: showsTools),
                id: \.id
            ) { row in
                switch row {
                case .item(let index, _): self.row(items[index], at: index, in: items, dates: dates)
                case .exchange(let exchange, _): self.row(exchange, in: items, dates: dates)
                case .live: live
                case .cards: cards
                }
            }
        }
        .environment(\.waitingAsks, BotAsk.waiting(in: items))
        .onAppear {
            window.hold(items)
            // Opening the chat reads it, unless a search is taking you somewhere already.
            if let itemID = thread.opened(), jump == nil {
                returnJump = MessageJump(contactID: thread.contactID, itemID: itemID)
            }
        }
        .onChange(of: thread.transcriptLoad) { window.reset(items) }
        .onChange(of: items.isEmpty) { window.reset(items) }
        .onChange(of: jump ?? returnJump, initial: true) { _, jump in if let jump { target = jump.itemID } }
        .onChange(of: hasCards, initial: true) { cardsAfter = hasCards ? items.last?.id ?? -1 : nil }
        .onChange(of: thread.transcriptLoad) { if hasCards { cardsAfter = items.last?.id ?? -1 } }
        // A card may be out of sight, or VoiceOver elsewhere in the chat.
        .onChange(of: waiting) { old, new in
            if let text = TranscriptAnnouncement.appeared(from: old, to: new, agent: agentName) {
                TranscriptAnnouncement.post(text)
            }
        }
        // The chat's widgets talk back to it.
        .environment(\.widgetChat, thread)
    }

    private var items: [TranscriptItem] { thread.state.items }
    private var exchanges: [BotExchange] { BotExchange.all(in: items) }
    /// The turn running now is one for another Bot: what it does shows inside its folded line.
    private var runsForABot: Bool { thread.state.isRunning && thread.turnIsForABot }
    /// The reply being written, as far as the chat shows it.
    private var draft: String { streamsReplies ? thread.state.draft : "" }
    private var cardsIndex: Int { Self.cardsIndex(in: items, after: cardsAfter) }

    /// A part of the transcript: an item, an exchange with another Bot folded into one line, the
    /// reply being written with what the turn is doing, or the cards waiting for you.
    enum Row: Equatable {
        case item(index: Int, id: Int)
        case exchange(BotExchange, id: Int)
        case live
        case cards

        /// An item's ID, not its index, which shifts when one is inserted earlier. Item IDs start at 0.
        /// An exchange goes by its first item's.
        var id: Int {
            switch self {
            case .item(_, let id), .exchange(_, let id): id
            case .live: -1
            case .cards: -2
            }
        }

        /// The items it shows.
        var items: Range<Int>? {
            switch self {
            case .item(let index, _): index..<(index + 1)
            case .exchange(let exchange, _): exchange.items
            case .live, .cards: nil
            }
        }
    }

    /// The items from `start` in order with the cards at `split`, each of `exchanges` as one row.
    /// What's live follows the newest message, so it sits above cards nothing has followed yet. The
    /// cards show wherever they sit, after the whole of an exchange they came in. Without
    /// `showingTools`, tool activity outside an exchange gets no row.
    nonisolated static func rows(
        of items: [TranscriptItem], cardsAt split: Int, from start: Int = 0, folding exchanges: [BotExchange] = [],
        showingTools: Bool = true
    ) -> [Row] {
        var rows: [Row] = []
        var index = 0
        while index < items.count {
            if let exchange = exchanges.first(where: { $0.items.lowerBound == index && !$0.items.isEmpty }) {
                rows.append(.exchange(exchange, id: items[index].id))
                index = exchange.items.upperBound
            } else {
                if showingTools || !items[index].isToolActivity {
                    rows.append(.item(index: index, id: items[index].id))
                }
                index += 1
            }
        }
        let cut = rows.firstIndex { ($0.items?.lowerBound ?? 0) >= split } ?? rows.count
        let tail: [Row] = cut < rows.count ? [.cards] + rows[cut...] + [.live] : [.live, .cards]
        return (Array(rows[..<cut]) + tail).filter { ($0.items?.upperBound ?? .max) > start }
    }

    @ViewBuilder private func row(_ exchange: BotExchange, in items: [TranscriptItem], dates: [Int: String])
        -> some View
    {
        let first = items[exchange.items.lowerBound]
        if let date = dates[first.id] { DateLabel(text: date) }
        let running = runsForABot && exchange.items.upperBound == items.count
        BotExchangeLine(
            exchange: exchange, items: items, agentName: agentName, running: running,
            draft: running ? draft : "",
            reveals: target.map { id in items[exchange.items].contains { $0.id == id } } == true
        )
        .transition(.settle)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func row(
        _ item: TranscriptItem, at index: Int, in items: [TranscriptItem], dates: [Int: String]
    ) -> some View {
        if let date = dates[item.id] { DateLabel(text: date) }
        let isLast = index + 1 == items.count
        let shown = Self.shown(items, at: index)
        let joins = Self.joins(items, at: index, dates: dates, showingTools: showsTools, draftBelow: !draft.isEmpty)
        ItemView(
            item: shown, agentName: agentName, joinsAbove: joins.above, joinsBelow: joins.below,
            spokenTexts: Self.spokenTexts(of: shown, in: items, at: index),
            working: isLast ? working : nil
        )
        .transition(item.arrival(streamed: streamsReplies))
        .accessibilityElement(children: .contain)
    }

    /// Whether a reply joins the replies shown either side of it: a date between them parts them,
    /// and a hidden tool line doesn't. The last one shown joins the reply being written.
    nonisolated static func joins(
        _ items: [TranscriptItem], at index: Int, dates: [Int: String], showingTools: Bool, draftBelow: Bool
    ) -> (above: Bool, below: Bool) {
        guard items[index].isReply else { return (false, false) }
        func shown(_ item: TranscriptItem) -> Bool { showingTools || !item.isToolActivity }
        let above = items[..<index].last(where: shown)
        let below = items[(index + 1)...].first(where: shown)
        return (
            above?.isReply == true && dates[items[index].id] == nil,
            below.map { $0.isReply && dates[$0.id] == nil } ?? draftBelow
        )
    }

    /// The reply being written and what the turn is doing, after the newest message.
    @ViewBuilder private var live: some View {
        if runsForABot {
            // Shown in the exchange's line.
        } else if !draft.isEmpty {
            // Becomes a transcript item when it ends, so it leaves without a fade.
            AgentBubble(joinsAbove: items.last?.isReply == true) {
                MarkdownView(draft, isBeingWritten: true)
            }
            .joined(items.last?.isReply == true)
            .transition(.asymmetric(insertion: .settle, removal: .identity))
        }
        if !runsForABot {
            if showsTools { LiveCards(live: thread.state.live) }
            // With tools hidden, the activity line that would say what's happening isn't shown.
            if let working, !lastItemIsActivity || !showsTools {
                WorkingRow(text: working).transition(.settle)
            }
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
    @Environment(\.editingFrom) private var editingFrom
    @Environment(\.waitingAsks) private var waitingAsks

    var body: some View {
        content
            // Sending the edit removes what follows the message being edited.
            .opacity(editingFrom.map { item.id > $0 } == true ? 0.4 : 1)
            .animation(.easeOut(duration: 0.15), value: editingFrom)
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
            MessageRow(
                item: item, text: text, author: agentName, agentName: agentName, isMine: false, readsAloud: true
            ) {
                AgentBubble(joinsAbove: joinsAbove, joinsBelow: joinsBelow) { MarkdownView(text) }
                    .environment(\.spokenTexts, spokenTexts)
            }
            .joined(joinsAbove)
        case .member(let id, let text):
            let author = author(id)
            MessageRow(
                item: item, text: text, author: author?.name ?? id, agentName: agentName, isMine: false,
                readsAloud: true, bubbleInset: author == nil ? 0 : 38
            ) {
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
        case .botMessage(let from, let text, _):
            BotMessageLine(from: from, text: text)
        case .botAsk(let ask):
            BotAskLine(ask: ask, waiting: waitingAsks.contains(ask.id))
        case .botAnswer(let answers):
            BotAnswerLine(answers: answers)
        case .output(let text):
            MessageRow(item: item, text: text, author: agentName, agentName: agentName, isMine: false) {
                CommandOutput(text: text)
            }
        case .background(let task, let result):
            MessageRow(
                item: item, text: result, author: agentName, agentName: agentName, isMine: false, readsAloud: true
            ) {
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

/// Your message as wide as its text: attachments above the bubble, and inside it what it quotes,
/// each quote with what you said to it.
struct UserBubbleContent: View {
    let text: String
    @Environment(\.sentImages) private var sentImages
    @Environment(\.messageTextSize) private var messageSize

    var body: some View {
        // Attachments travel as `@image:`/`@file:` lines after the text; they show above it.
        let (withQuote, attachments) = AttachmentRef.split(text)
        let parts = QuotedMessage.parts(withQuote)
        // Audio and video you sent get a player; the rest show as tiles.
        let (playable, tiles) = (
            attachments.filter { $0.kind == .file && MediaLoading.kind(of: $0.path).isPlayable },
            attachments.filter { $0.kind != .file || !MediaLoading.kind(of: $0.path).isPlayable }
        )
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(playable, id: \.path) { ref in
                MediaView(path: ref.path)
                    .padding(10)
                    .zoomedFrame(maxWidth: 440)
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
            if !parts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        switch part {
                        case .quote(let quote):
                            Text(quote)
                                .scaledFont(size: 13)
                                .foregroundStyle(Theme.userBubbleInk.opacity(0.7))
                                .lineLimit(2)
                                .padding(.leading, 9)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.userBubbleInk.opacity(0.35)).frame(width: 2)
                                }
                                // A little more room above a quote that follows your words.
                                .padding(.top, index > 0 && !parts[index - 1].isQuote ? 4 : 0)
                        case .text(let words):
                            #if os(macOS)
                                MessageText(content: .mine(words, size: messageSize))
                            #else
                                // Links underlined in the bubble's own ink: the link colour wouldn't
                                // read on the bubble.
                                Text(Links.detect(in: words).underliningLinks())
                                    .messageFont()
                                    .tint(Theme.userBubbleInk)
                            #endif
                        }
                    }
                }
                .foregroundStyle(Theme.userBubbleInk)
                .messageTextSelection()
                .padding(.horizontal, Theme.bubblePadding)
                .padding(.vertical, 9)
                .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: 18))
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
        let now = ActivitySummary.current(in: steps) ?? working
        let failed = steps.contains { $0.state == .failed }
        FoldedRow(
            symbol: now == nil ? ActivitySummary.symbol(for: steps) : nil,
            tint: failed ? Theme.danger : Theme.secondaryInk,
            openByDefault: now != nil
        ) {
            if let now {
                WorkingRow(text: now)
            } else {
                Text(ActivitySummary.line(for: steps, agent: agentName))
            }
        } rows: {
            // While it runs, only the newest steps, so the line grows by a few rows at most.
            let shown = now == nil ? steps[...] : steps.suffix(Self.liveSteps)
            if shown.count < steps.count {
                Text("\(steps.count - shown.count) earlier steps")
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.secondaryInk)
            }
            ForEach(shown) { step in
                StepRow(step: step)
            }
        }
    }

    private static let liveSteps = 3
}

private struct StepRow: View {
    let step: ToolStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(ActivitySummary.verb(for: step.name))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1)
                .zoomedFrame(width: 52, alignment: .leading)
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
                .messageTextSelection()
                .padding(12)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.selection.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
