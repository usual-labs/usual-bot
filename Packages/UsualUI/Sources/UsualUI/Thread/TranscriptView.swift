import HermesKit
import SwiftUI

/// The scrolling conversation: your messages as bubbles, the agent's replies as full-width text,
/// tool calls folded into one line each, and system notices centred.
struct TranscriptView: View {
    let thread: ChatThread
    let agentName: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
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
                    thread.questions.isEmpty
                {
                    TypingIndicator()
                }
                ForEach(thread.approvals) { approval in
                    ApprovalCard(approval: approval, agentName: agentName) { thread.answer(approval, with: $0) }
                }
                ForEach(thread.questions) { prompt in
                    QuestionCard(
                        prompt: prompt, agentName: agentName, answer: { thread.answer(prompt, with: $0) },
                        skip: { thread.skip(prompt) })
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }

    private var lastItemIsLiveActivity: Bool {
        guard case .activity(let steps) = thread.state.items.last?.content else { return false }
        return steps.contains { $0.state == .running }
    }
}

private struct ItemView: View {
    let item: TranscriptItem
    let agentName: String

    var body: some View {
        switch item.content {
        case .user(let text):
            HStack {
                Spacer(minLength: 64)
                Text(text)
                    .font(.system(size: 15))
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
        case .assistant(let text):
            MarkdownView(text)
        case .activity(let steps):
            ActivityLine(steps: steps, agentName: agentName)
        case .notice(let text):
            NoticeLine(text: text)
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
private struct TypingIndicator: View {
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
