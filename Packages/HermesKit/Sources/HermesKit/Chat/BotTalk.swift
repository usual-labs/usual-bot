import Foundation

/// A message this chat's Bot sent other Bots with Hermes's `message_agent` (`tools/bot_mode_dm.py`).
/// Hermes delivers it into each one's Bot Chat and hands back a receipt at once; the answer comes
/// later, as a background process finishing (`BotAnswer`).
public struct BotAsk: Equatable, Sendable, Codable {
    /// The tool call's ID.
    public let id: String
    /// Who it went to, as the Bot named them and without `@`: a profile, a Bot's name, or a
    /// `peer/agent` on another gateway. Up to eight at once, for one combined answer.
    public let to: [String]
    public let message: String
    /// `false` for a note: nothing comes back.
    public let wantsReply: Bool
    public var state: ToolStep.State
    /// Why Hermes didn't send it, such as a chain of Bots that ran too long.
    public var error: String?

    static let toolName = "message_agent"

    public init(
        id: String, to: [String], message: String, wantsReply: Bool, state: ToolStep.State, error: String? = nil
    ) {
        self.id = id
        self.to = to
        self.message = message
        self.wantsReply = wantsReply
        self.state = state
        self.error = error
    }

    /// A `message_agent` call's arguments; `nil` for one that only cancels an earlier message.
    init?(id: String, args: JSONValue?) {
        guard let args, args["cancel"]?.stringValue?.nonBlank == nil,
            let target = args["target"]?.stringValue?.nonBlank
        else { return nil }
        let to = target.split(separator: ",").map {
            String($0.trimmingCharacters(in: .whitespaces).drop { $0 == "@" })
        }.filter { !$0.isEmpty }
        guard !to.isEmpty else { return nil }
        // Models send `expects_reply` as a bool or spelt out.
        let reply = args["expects_reply"]
        let note = reply?.boolValue == false || reply?.stringValue?.lowercased() == "false"
        self.init(
            id: id, to: to, message: args["message"]?.stringValue ?? "", wantsReply: !note, state: .running)
    }

    /// What Hermes answered the call with: a receipt, or why it sent nothing.
    mutating func read(result: JSONValue?) {
        var result = result
        if let text = result?.stringValue, let data = text.data(using: .utf8) {
            result = try? JSONDecoder().decode(JSONValue.self, from: data)
        }
        if let error = result?["error"]?.stringValue?.nonBlank {
            state = .failed
            self.error = error
        } else {
            state = .done
        }
    }
}

/// What came back from the Bots a `BotAsk` went to: one answer each.
public struct BotAnswer: Equatable, Sendable, Codable {
    public enum Outcome: Equatable, Sendable, Codable {
        /// Its final reply, Markdown.
        case answered(String)
        /// It finished its turn without a reply.
        case silent
        /// It finished, but the reply didn't reach this chat: Hermes cut a long one-line report to
        /// nothing (NousResearch/hermes-agent#152075).
        case lost
        /// It didn't answer in time; the request is still on its side.
        case pending(String)
        /// It never answered, and why.
        case failed(String)
    }

    /// The Bot's profile or `peer/agent`, without `@`; empty when Hermes didn't say.
    public let from: String
    public let outcome: Outcome

    public init(from: String, outcome: Outcome) {
        self.from = from
        self.outcome = outcome
    }

    /// The answers a background process's notice carries, when it's the one `message_agent`
    /// started (`--run-delivery` for one Bot, `--fan-out` for several); `nil` for any other process.
    /// It prints one JSON line, after anything the runner's tools printed first.
    static func parse(_ report: ProcessReport) -> [BotAnswer]? {
        guard report.command.contains("bot_mode_dm.py"),
            report.command.contains("--run-delivery") || report.command.contains("--fan-out")
        else { return nil }
        let line = report.output.split(separator: "\n").last { $0.hasPrefix("{") }
        guard let line, let data = line.data(using: .utf8),
            let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            // Nothing to read: Hermes cut it, or the runner died before printing.
            let profile = Self.profile(in: report.command)
            return [BotAnswer(from: profile, outcome: report.exitCode == 0 ? .lost : .failed(""))]
        }
        if case .array(let entries) = json["replies"] {
            return entries.map { entry in
                BotAnswer(from: Self.handle(entry["to"]?.stringValue) ?? "", outcome: Self.outcome(of: entry))
            }
        }
        let from = Self.handle(json["outcome"]?.stringValue) ?? Self.profile(in: report.command)
        return [BotAnswer(from: from, outcome: Self.outcome(of: json))]
    }

    private static func outcome(of entry: JSONValue) -> Outcome {
        let reason = (entry["error"]?.stringValue?.nonBlank ?? entry["outcome"]?.stringValue ?? "")
        switch entry["status"]?.stringValue {
        case "settled":
            return entry["reply"]?.stringValue?.nonBlank.map { .answered($0) } ?? .silent
        case "queued", "claimed", "pending", "ambiguous":
            return .pending(entry["outcome"]?.stringValue ?? reason)
        case "cancelled":
            return .failed(String(localized: "The request was cancelled."))
        default:
            return .failed(reason)
        }
    }

    /// `@dr-eggbot answered.` → `dr-eggbot`: Hermes's outcome sentence starts with who it was.
    private static func handle(_ text: String?) -> String? {
        guard let text, text.hasPrefix("@") else { return nil }
        let name = text.dropFirst().prefix { !$0.isWhitespace && $0 != "," }
        return name.isEmpty ? nil : String(name)
    }

    /// The profile a delivery ran in: `… hermes -p <profile>`.
    private static func profile(in command: String) -> String {
        let words = command.split(whereSeparator: \.isWhitespace)
        guard let flag = words.lastIndex(of: "-p"), flag + 1 < words.count else { return "" }
        return String(words[flag + 1])
    }
}

/// A message from another Bot that started a turn in this chat, and what this Bot did for it. The
/// chat folds the lot into one line: the Bot's reply goes back to the other Bot, not to you.
public struct BotExchange: Equatable, Sendable {
    /// The other Bot's name, as Hermes signed the message.
    public let from: String
    /// A note wanting no reply.
    public let isNote: Bool
    /// The other Bot's message, then everything up to the next turn.
    public let items: Range<Int>

    /// The exchanges in a chat. Each runs from a Bot's message to the next thing that starts a turn:
    /// a message of yours, another Bot's, a routine's or process's result.
    public static func all(in items: [TranscriptItem]) -> [BotExchange] {
        var found: [BotExchange] = []
        var open: (from: String, isNote: Bool, start: Int)?
        for (index, item) in items.enumerated() where item.startsTurn {
            if let open { found.append(BotExchange(from: open.from, isNote: open.isNote, items: open.start..<index)) }
            open = nil
            if case .botMessage(let from, _, let isNote) = item.content { open = (from, isNote, index) }
        }
        if let open { found.append(BotExchange(from: open.from, isNote: open.isNote, items: open.start..<items.count)) }
        return found
    }

    /// The exchange the chat's newest items belong to, if they're one.
    public static func last(in items: [TranscriptItem]) -> BotExchange? {
        guard let start = items.lastIndex(where: \.startsTurn),
            case .botMessage(let from, _, let isNote) = items[start].content
        else { return nil }
        return BotExchange(from: from, isNote: isNote, items: start..<items.count)
    }

    /// The tool calls the Bot made for it.
    public func steps(in items: [TranscriptItem]) -> Int {
        items[self.items].reduce(0) { count, item in
            switch item.content {
            case .activity(let steps): count + steps.count
            case .botAsk: count + 1
            default: count
            }
        }
    }

    /// What the sidebar and the line say about it.
    public func summary(running: Bool) -> String {
        if running { return String(localized: "Working for \(from)…") }
        return isNote ? String(localized: "Note from \(from)") : String(localized: "Talked with \(from)")
    }
}

extension TranscriptItem {
    /// Whether this item begins a turn, rather than being part of the one before.
    public var startsTurn: Bool {
        switch content {
        case .user, .botMessage, .botAnswer, .result, .background: true
        // A goal's own turn; other notices belong to the turn they're in.
        case .notice(let text): text == GatewayTurn.goalStep
        default: false
        }
    }
}

extension BotAsk {
    /// Hermes gives up waiting for an answer after 30 minutes (`_LIVE_WAIT_MAX_SECONDS`) and reports
    /// it as pending, so a message older than this with nothing back isn't being waited on.
    static let answerWindow: TimeInterval = 32 * 60

    /// The messages in `items` still waiting for an answer. History keeps no receipt, so each answer
    /// is matched to the earliest message waiting on that Bot, or on anyone.
    public static func waiting(in items: [TranscriptItem], now: Date = .now) -> Set<String> {
        var open: [(id: String, to: Set<String>)] = []
        for item in items {
            switch item.content {
            case .botAsk(let ask) where ask.wantsReply && ask.state != .failed:
                if let date = item.date, now.timeIntervalSince(date) > answerWindow { continue }
                open.append((ask.id, Set(ask.to.map { $0.lowercased() })))
            case .botAnswer(let answers):
                let from = Set(answers.map { $0.from.lowercased() })
                if let index = open.firstIndex(where: { !$0.to.isDisjoint(with: from) }) ?? open.indices.first {
                    open.remove(at: index)
                }
            default:
                break
            }
        }
        return Set(open.map(\.id))
    }
}

extension Array where Element == Contact {
    /// The Bot a `message_agent` target or answer names: its profile, its name or its @-handle
    /// (`Dr. Foo` → `dr-foo`). `hermes` is the default profile. `nil` for a Bot on another gateway.
    public func bot(named handle: String) -> Contact? {
        let wanted = handle.drop { $0 == "@" }.lowercased()
        guard !wanted.isEmpty else { return nil }
        let profile = wanted == "hermes" ? "default" : wanted
        func slug(_ name: String) -> String {
            name.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
        }
        return first { ($0.details?.profile ?? $0.id).lowercased() == profile }
            ?? first { $0.name.lowercased() == wanted || slug($0.name) == wanted }
    }

    /// What to call that Bot: its name here, or one made from the handle.
    public func botName(_ handle: String) -> String {
        if let contact = bot(named: handle) { return contact.name }
        if handle.isEmpty { return String(localized: "The other Bot") }
        return handle.contains("/") ? handle : Contact.friendlyName(forProfile: handle)
    }
}
