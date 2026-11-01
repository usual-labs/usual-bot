import HermesKit
import SwiftUI

/// The scrolling conversation: your messages as bubbles, the agent's replies as full-width text,
/// tool calls folded into one line each, and system notices centred.
struct TranscriptView: View {
    let thread: ChatThread
    let agentName: String

    var body: some View {
        // A reloaded transcript numbers its items afresh, so a position kept by item would now
        // point at an older message: start over at the newest one.
        ConversationScroll(reload: thread.transcriptLoad) {
            if let banner = thread.banner {
                NoticeLine(text: banner)
            }
            if thread.state.items.isEmpty, !thread.state.isRunning {
                NoticeLine(text: String(localized: "Say hello to \(agentName)."))
                    .padding(.top, 40)
            }
            ForEach(thread.state.items) { item in
                ItemView(item: item, agentName: agentName)
            }
            if !thread.state.draft.isEmpty {
                MarkdownView(thread.state.draft)
            } else if thread.state.isRunning, !lastItemIsLiveActivity, thread.approvals.isEmpty,
                thread.questions.isEmpty, thread.secrets.isEmpty, thread.vaultPrompts.isEmpty
            {
                TypingIndicator()
            }
            VaultCards(thread: thread, agentName: agentName)
            ForEach(thread.approvals) { approval in
                ApprovalCard(approval: approval, agentName: agentName) { thread.answer(approval, with: $0) }
            }
            ForEach(thread.questions) { prompt in
                QuestionCard(
                    prompt: prompt, agentName: agentName, answer: { thread.answer(prompt, with: $0) },
                    skip: { thread.skip(prompt) })
            }
            ForEach(thread.secrets) { prompt in
                SecretCard(
                    prompt: prompt, agentName: agentName, isUnencrypted: thread.isLinkUnencrypted,
                    answer: { thread.answer(prompt, with: $0) }, skip: { thread.skip(prompt) })
            }
        }
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
    @ViewBuilder let content: Content
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
            LazyVStack(alignment: .leading, spacing: 14) {
                content
                Color.clear.frame(height: 0).id(Self.end)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 780)
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
        .onAppear(perform: scrollToEnd)
        .onChange(of: reload) {
            followsEnd = true
            scrollToEnd()
        }
    }

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

struct ItemView: View {
    let item: TranscriptItem
    let agentName: String
    /// Rooms only: resolves a member ID to its author.
    var author: (String) -> MemberAuthor? = { _ in nil }

    var body: some View {
        switch item.content {
        case .user(let text):
            MessageRow(item: item, text: QuotedMessage.split(AttachmentRef.split(text).text).text, isMine: true) {
                UserBubbleContent(text: text)
            }
        case .assistant(let text):
            MessageRow(item: item, text: text, isMine: false) { MarkdownView(text) }
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
                        MarkdownView(text)
                            // Files a member names live in its own profile.
                            .environment(\.mediaProfile, author.map { $0.contact.details?.profile ?? $0.contact.id })
                    }
                }
            }
        case .activity(let steps):
            ActivityLine(steps: steps, agentName: agentName)
        case .notice(let text):
            NoticeLine(text: text)
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
                    MarkdownView(result)
                }
            }
        }
    }
}

/// Your message: a dark bubble on the right.
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
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(
                    Theme.userBubble,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6,
                        topTrailingRadius: 20))
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

/// One centred line for a run of tool calls; click to see each step.
private struct ActivityLine: View {
    let steps: [ToolStep]
    let agentName: String
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    if steps.contains(where: { $0.state == .running }) {
                        ProgressView().controlSize(.mini)
                    }
                    Text(ActivitySummary.line(for: steps, agent: agentName))
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
                .frame(maxWidth: 520, alignment: .leading)
                .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
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

/// Three dots that pulse while the agent is thinking.
struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 2.5
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Theme.secondaryInk)
                        .frame(width: 7, height: 7)
                        .opacity(reduceMotion ? 0.7 : 0.35 + 0.65 * max(0, sin(phase - Double(index) * 0.6)))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(
                Theme.codeFill,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18))
        }
        .accessibilityLabel(Text("Working"))
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
