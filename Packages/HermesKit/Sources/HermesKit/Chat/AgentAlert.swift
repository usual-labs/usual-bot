import Foundation

/// Something an agent did that you aren't looking at.
public struct AgentAlert: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A reply, or a message the agent sent by itself.
        case message
        /// An agent is waiting on you: an approval, a question, a secret or a stopped room reply.
        case needsYou
        case taskFinished
    }

    /// Stable for a request, so its notification can be taken back.
    public let id: String
    public let kind: Kind
    /// Who in a room spoke, or the task that finished.
    public let subtitle: String?
    /// What was said or asked, in plain words. May be private: previews can be turned off.
    public let preview: String

    /// Markdown's words on one line, as a notification shows them: no heading, list, quote, table
    /// or code fence marks, bold and code as plain words, and links by their text. Not for a command
    /// to approve, where a `*` is part of the command.
    ///
    /// `Integrations/hermes-push/plain.py` does the same to what the gateway pushes.
    public static func plain(_ markdown: String) -> String {
        let inline = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var inCode = false
        var lines: [String] = []
        for line in markdown.split(whereSeparator: \.isNewline) {
            var line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inCode.toggle()
            } else if inCode {
                lines.append(line)
            } else if line.contains(where: { !"-*_=|: ".contains($0) }) {
                // Any other line is a rule, a table's divider or the line under a heading.
                line = line.replacing(/^(>\s*)*(#{1,6}\s+|[-*+]\s+)?/, with: "")
                if line.hasPrefix("|") {
                    let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    line = cells.joined(separator: " · ")
                }
                let words = try? AttributedString(markdown: line, options: inline)
                lines.append(words.map { String($0.characters) } ?? line)
            }
        }
        return lines.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension ChatThread {
    func announce(_ reply: TranscriptItem) {
        guard case .assistant(let text) = reply.content else { return }
        alert?(AgentAlert(id: UUID().uuidString, kind: .message, subtitle: nil, preview: AgentAlert.plain(text)))
    }

    /// Alerts about the newest reply in `history`, which came in while the app wasn't connected.
    func announceReply(in history: [HistoryMessage]) {
        guard let text = history.last(where: { $0.role == "assistant" && $0.text?.nonBlank != nil })?.text else {
            return
        }
        alert?(AgentAlert(id: UUID().uuidString, kind: .message, subtitle: nil, preview: AgentAlert.plain(text)))
    }

    /// Alerts about what's newly waiting on you, and takes back what no longer is.
    func announceRequests() {
        let waiting = waitingRequests
        for request in waiting where !announcedRequests.contains(request.id) && !isVisible {
            alert?(AgentAlert(id: request.id, kind: .needsYou, subtitle: nil, preview: request.text))
        }
        let ids = Set(waiting.map(\.id))
        for id in announcedRequests.subtracting(ids) { alertWithdrawn?(id) }
        announcedRequests = ids
    }

    private var waitingRequests: [(id: String, text: String)] {
        let commands = approvals.map {
            (id: $0.id, text: String(localized: "Wants to run “\($0.shortCommand)”"))
        }
        let asked = questions.map {
            let question = $0.questions.first.map { AgentAlert.plain($0.text) }
            return (id: $0.id, text: question ?? String(localized: "Has a question"))
        }
        let secrets = secrets.map { prompt in
            switch prompt.kind {
            case .secret(let name, _): (id: prompt.id, text: String(localized: "Asks for \(name)"))
            case .sudo: (id: prompt.id, text: String(localized: "Asks for the sudo password"))
            }
        }
        let vault = vaultPrompts.map { (id: $0.id, text: String(localized: "Needs you for a sign-in")) }
        let apps = connection.map { [(id: $0.request.id, text: $0.request.alertText)] } ?? []
        return commands + asked + secrets + vault + apps
    }
}
