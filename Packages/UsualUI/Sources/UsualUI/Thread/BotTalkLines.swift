import HermesKit
import SwiftUI

/// The Bots on this gateway, to name the ones a message went to or came from, and to open a chat
/// with one. `nil` outside the main window: names then come from the handles.
struct BotDirectory {
    let contacts: [Contact]
    let open: (Contact.ID) -> Void

    func name(_ handle: String) -> String { contacts.botName(handle) }
}

extension EnvironmentValues {
    @Entry var botDirectory: BotDirectory?
    /// The messages to other Bots in this chat still waiting for an answer (`BotAsk.waiting`).
    @Entry var waitingAsks: Set<String> = []
}

/// A message this chat's Bot sent other Bots: who to, and the message behind it.
struct BotAskLine: View {
    let ask: BotAsk
    /// Still waiting for the answer.
    let waiting: Bool
    @Environment(\.botDirectory) private var directory

    var body: some View {
        FoldedRow(symbol: symbol, tint: ask.state == .failed ? Theme.danger : Theme.secondaryInk) {
            Text(title).lineLimit(1)
        } rows: {
            if let error = ask.error {
                Caption(text: error)
            }
            ReportPeek(text: ask.message, style: .markdown)
        }
    }

    private var names: String {
        let names = ask.to.map { directory?.name($0) ?? [Contact]().botName($0) }
        return names.formatted(.list(type: .and))
    }

    private var title: String {
        if ask.state == .failed { return String(localized: "Couldn't message \(names)") }
        if !ask.wantsReply { return String(localized: "Told \(names)") }
        let asked = String(localized: "Asked \(names)")
        return waiting ? asked + " · " + String(localized: "waiting") : asked
    }

    private var symbol: String {
        if ask.state == .failed { return "xmark.circle" }
        return ask.wantsReply ? "paperplane" : "paperplane.circle"
    }
}

/// What came back from the Bots this chat's Bot messaged.
struct BotAnswerLine: View {
    let answers: [BotAnswer]
    @Environment(\.botDirectory) private var directory

    var body: some View {
        if let answer = answers.first, answers.count == 1 {
            OneBotAnswer(answer: answer)
        } else {
            FoldedRow(symbol: failed > 0 ? "xmark.circle" : "arrowshape.turn.up.left", tint: Theme.secondaryInk) {
                Text(title).lineLimit(1)
            } rows: {
                ForEach(Array(answers.enumerated()), id: \.offset) { _, answer in
                    OneBotAnswer(answer: answer)
                }
            }
        }
    }

    private var failed: Int { answers.count { if case .answered = $0.outcome { false } else { true } } }

    private var title: String {
        let answered = answers.count - failed
        let line = String(localized: "\(answered) of \(answers.count) Bots answered")
        return failed == 0 ? String(localized: "\(answers.count) Bots answered") : line
    }
}

private struct OneBotAnswer: View {
    let answer: BotAnswer
    @Environment(\.botDirectory) private var directory

    var body: some View {
        switch answer.outcome {
        case .answered(let reply):
            FoldedRow(symbol: "arrowshape.turn.up.left") {
                Text("\(name) answered").lineLimit(1)
            } rows: {
                ReportPeek(text: reply, style: .markdown)
            }
        case .silent:
            FoldedRow(symbol: "checkmark.circle", opens: false) {
                Text("\(name) finished without replying").lineLimit(1)
            } rows: {
                EmptyView()
            }
        case .lost:
            VStack(alignment: .leading, spacing: 6) {
                FoldedRow(symbol: "exclamationmark.circle", opens: false) {
                    Text("\(name) finished, but its reply didn't come through").lineLimit(2)
                } rows: {
                    EmptyView()
                }
                if let directory, let contact = directory.contacts.bot(named: answer.from) {
                    Button("Open \(contact.name)’s Chat") { directory.open(contact.id) }
                        .buttonStyle(.clickable(.bordered))
                        .controlSize(.small)
                        .padding(.leading, 28)
                }
            }
        case .pending(let reason):
            FoldedRow(symbol: "clock", opens: !reason.isEmpty) {
                Text("\(name) didn't answer in time").lineLimit(1)
            } rows: {
                Caption(text: reason)
            }
        case .failed(let reason):
            FoldedRow(symbol: "xmark.circle", tint: Theme.danger, opens: !reason.isEmpty) {
                Text("\(name) couldn't answer").lineLimit(1)
            } rows: {
                Caption(text: reason)
            }
        }
    }

    private var name: String { directory?.name(answer.from) ?? [Contact]().botName(answer.from) }
}

/// Another Bot's message on its own, outside the fold an exchange usually gets.
struct BotMessageLine: View {
    let from: String
    let text: String

    var body: some View {
        FoldedRow(symbol: "bubble.left", opens: !text.isEmpty) {
            Text("Message from \(from)").lineLimit(1)
        } rows: {
            ReportPeek(text: text, style: .markdown)
        }
    }
}

/// Another Bot's message and everything this Bot did for it, as one folded line. The reply went
/// back to that Bot, so none of it is a message to you: it stays folded until you open it.
struct BotExchangeLine: View {
    let exchange: BotExchange
    let items: [TranscriptItem]
    let agentName: String
    let running: Bool
    /// The reply being written, shown inside while it runs.
    var draft = ""
    /// Opens the line: a search found something in it.
    var reveals = false

    var body: some View {
        FoldedRow(symbol: running ? nil : symbol, openByDefault: reveals) {
            if running {
                WorkingRow(text: exchange.summary(running: true))
            } else {
                Text(title).lineLimit(1)
            }
        } rows: {
            if case .botMessage(_, let text, _) = items[exchange.items.lowerBound].content, !text.isEmpty {
                Caption(text: String(localized: "\(exchange.from) wrote"))
                ReportPeek(text: text, style: .markdown)
            }
            ForEach(items[exchange.items].dropFirst()) { item in
                ItemView(item: item, agentName: agentName)
            }
            if running, !draft.isEmpty {
                AgentBubble { MarkdownView(draft, isBeingWritten: true) }
            }
        }
    }

    private var symbol: String { exchange.isNote ? "bubble.left" : "bubble.left.and.bubble.right" }

    private var title: String {
        let steps = exchange.steps(in: items)
        let summary = exchange.summary(running: false)
        guard steps > 0 else { return summary }
        return summary + " · " + (steps == 1 ? String(localized: "1 step") : String(localized: "\(steps) steps"))
    }
}
