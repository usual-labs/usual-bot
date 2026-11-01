import HermesKit
import SwiftUI

/// The scrolling conversation: bubbles for you and the agent, tool calls folded into one line each,
/// and system notices centred.
struct TranscriptView: View {
    let thread: ChatThread
    let agentName: String

    var body: some View {
        // A reloaded transcript numbers its items afresh, so a position kept by item would now
        // point at an older message: start over at the newest one.
        ConversationScroll(reload: thread.transcriptLoad, arrival: arrival) {
            if let banner = thread.banner {
                NoticeLine(text: banner)
            }
            if thread.state.items.isEmpty, !thread.state.isRunning {
                NoticeLine(text: String(localized: "Say hello to \(agentName)."))
                    .padding(.top, 40)
            }
            let items = thread.state.items
            ForEach(Array(zip(items.indices, items)), id: \.1.id) { index, item in
                ItemView(
                    item: item, agentName: agentName,
                    joinsAbove: item.isReply && index > 0 && items[index - 1].isReply,
                    joinsBelow: item.isReply
                        && (index + 1 < items.count ? items[index + 1].isReply : !thread.state.draft.isEmpty)
                )
                .transition(item.arrival)
            }
            if !thread.state.draft.isEmpty {
                // Becomes a transcript item when it ends, so it leaves without a fade.
                AgentBubble(joinsAbove: items.last?.isReply == true) { MarkdownView(thread.state.draft) }
                    .joined(items.last?.isReply == true)
                    .transition(.asymmetric(insertion: .settle, removal: .identity))
            } else if thread.state.isRunning, !lastItemIsLiveActivity, thread.approvals.isEmpty,
                thread.questions.isEmpty, thread.secrets.isEmpty, thread.vaultPrompts.isEmpty
            {
                WorkingRow(text: String(localized: "Thinking…")).transition(.settle)
            }
            VaultCards(thread: thread, agentName: agentName).transition(.settle)
            ForEach(thread.approvals) { approval in
                ApprovalCard(approval: approval, agentName: agentName) { thread.answer(approval, with: $0) }
                    .transition(.settle)
            }
            ForEach(thread.questions) { prompt in
                QuestionCard(
                    prompt: prompt, agentName: agentName, answer: { thread.answer(prompt, with: $0) },
                    skip: { thread.skip(prompt) }
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
    }

    /// Changes when something arrives at the end of the conversation.
    private var arrival: [Int] {
        [
            thread.state.items.count, thread.state.draft.isEmpty ? 0 : 1, thread.state.isRunning ? 1 : 0,
            thread.vaultPrompts.count, thread.approvals.count, thread.questions.count, thread.secrets.count,
        ]
    }

    private var lastItemIsLiveActivity: Bool {
        guard case .activity(let steps) = thread.state.items.last?.content else { return false }
        return steps.contains { $0.state == .running }
    }
}

/// A conversation's scrolling column, opened at its newest message and kept there as it grows, until
/// you scroll away from it.
struct ConversationScroll<Content: View>: View {
    /// Changes when the conversation is reloaded; it then scrolls back to the newest message.
    var reload = 0
    /// Changes when something arrives at the end, which animates in. A reload's rows don't.
    var arrival: [Int] = []
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settledReload = 0
    @State private var position = ScrollPosition()
    /// Off once you've scrolled away from the end. Measuring alone can't tell: the lazy stack's
    /// estimates move the end while nobody scrolls.
    @State private var followsEnd = true
    @State private var isNearEnd = true

    /// The column's last view. Scrolling to it places the newest message exactly; scrolling to the
    /// bottom edge trusts the lazy stack's estimate of rows it hasn't measured, which on iPhone
    /// left a long chat parked in blank space past its end.
    private static var end: String { "end" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                content
                Color.clear.frame(height: 0).id(Self.end)
            }
            .animation(reduceMotion || reload != settledReload ? nil : Self.arrive, value: arrival)
            .padding(.vertical, 16)
            // Edge to edge with the message box.
            .frame(maxWidth: 780)
            .padding(.horizontal, ThreadPane.composerMargin)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        // iPhone: scrolling the conversation puts the keyboard away, as in Messages.
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onScrollPhaseChange { old, new in
            if new.isByHand {
                followsEnd = false
            } else if old.isByHand {
                followsEnd = isNearEnd
            }
        }
        .onScrollGeometryChange(for: Bool.self, of: \.isNearEnd) { _, new in isNearEnd = new }
        // The anchor usually keeps up, but not with a column that started shorter than its window,
        // nor after a scroll to the end marker. The marker is no help here: until a new row is laid
        // out it's still above it, so scrolling to it would pull the row back under the box.
        .onScrollGeometryChange(for: CGFloat.self, of: \.endY) { _, end in
            if followsEnd { position.scrollTo(y: end) }
        }
        .onAppear {
            // A chat that's already loaded has nothing to settle.
            settledReload = reload
            scrollToEnd()
        }
        .onChange(of: reload) {
            settledReload = reload
            followsEnd = true
            scrollToEnd()
        }
    }

    /// Quick, with the slightest overshoot.
    private static var arrive: Animation { .spring(duration: 0.32, bounce: 0.12) }

    private func scrollToEnd() {
        position.scrollTo(id: Self.end, anchor: .bottom)
    }
}

extension ScrollPhase {
    /// Moving under your finger, wheel or trackpad, not because the app scrolled.
    fileprivate var isByHand: Bool { self == .tracking || self == .interacting || self == .decelerating }
}

extension ScrollGeometry {
    /// Where the column's end is for `ScrollPosition`, which counts from the content's top.
    /// `containerSize` leaves out the bars.
    fileprivate var endY: CGFloat { max(contentSize.height - containerSize.height, 0) }

    /// Allows for the end marker, which stops 16 pt short inside the column's padding.
    /// `contentOffset` counts from behind the top bar.
    fileprivate var isNearEnd: Bool { contentOffset.y + contentInsets.top >= endY - 40 }
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

    /// How the item comes in. A reply was on screen as a draft, so it swaps in without a move.
    fileprivate var arrival: AnyTransition {
        switch content {
        case .user: .rise
        case .assistant: .identity
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
    /// Rooms only: resolves a member ID to its author.
    var author: (String) -> MemberAuthor? = { _ in nil }

    var body: some View {
        switch item.content {
        case .user(let text):
            MessageRow(item: item, text: QuotedMessage.split(AttachmentRef.split(text).text).text, isMine: true) {
                UserBubbleContent(text: text)
            }
        case .assistant(let text):
            MessageRow(item: item, text: text, isMine: false) {
                AgentBubble(joinsAbove: joinsAbove, joinsBelow: joinsBelow) { MarkdownView(text) }
            }
            .joined(joinsAbove)
        case .member(let id, let text):
            let author = author(id)
            MessageRow(item: item, text: text, isMine: false) {
                HStack(alignment: .top, spacing: 10) {
                    if let author {
                        AgentAvatar(contact: author.contact, size: 28)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(author?.name ?? id)
                            .font(.system(size: 12.5, weight: .semibold))
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
            ActivityLine(steps: steps, agentName: agentName)
        case .notice(let text):
            NoticeLine(text: text)
        case .result(let title, let detail):
            ResultLine(title: title, detail: detail)
        case .output(let text):
            MessageRow(item: item, text: text, isMine: false) { CommandOutput(text: text) }
        case .background(let task, let result):
            MessageRow(item: item, text: result, isMine: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Background task: \(task)").lineLimit(2)
                    } icon: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .font(.system(size: 12.5, weight: .medium))
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
    @Environment(\.chatContact) private var contact

    var body: some View {
        // Attachments travel as `@image:`/`@file:` lines after the text; they show above it.
        let (withQuote, attachments) = AttachmentRef.split(text)
        let (quote, body) = QuotedMessage.split(withQuote)
        VStack(alignment: .trailing, spacing: 6) {
            if !attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(attachments, id: \.path) { ref in
                        AttachmentTile(
                            kind: ref.kind, name: ref.name, imageData: sentImages[ref.path], gatewayPath: ref.path)
                    }
                }
            }
            if !body.isEmpty || quote != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let quote {
                        // The message this one replies to.
                        Text(quote)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.userBubbleInk.opacity(0.7))
                            .lineLimit(2)
                            .padding(.leading, 9)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.userBubbleInk.opacity(0.35)).frame(width: 2)
                            }
                    }
                    if !body.isEmpty {
                        Text(body)
                            .messageFont()
                    }
                }
                .foregroundStyle(Theme.userBubbleInk)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
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
            .font(.system(size: 13))
            .foregroundStyle(Theme.secondaryInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// One quiet line for a run of tool calls, or what's happening now; click to see each step.
private struct ActivityLine: View {
    let steps: [ToolStep]
    let agentName: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if let now = ActivitySummary.current(in: steps) {
                        WorkingRow(text: now)
                    } else {
                        Text(ActivitySummary.line(for: steps, agent: agentName))
                            .padding(.leading, 12)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(steps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: Theme.bubbleWidth, alignment: .leading)
                .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .font(.system(size: 12.5, design: .monospaced))
    }
}

/// What a Hermes command printed: terminal text, so monospaced and never wrapped (its columns
/// line up); wide output scrolls sideways.
struct CommandOutput: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(size: 12.5, design: .monospaced))
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
