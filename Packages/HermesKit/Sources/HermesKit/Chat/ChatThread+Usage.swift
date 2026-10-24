import Foundation

/// How much of the model's context a chat fills, and the tokens it has used, as the gateway
/// reports them (`session.usage`, and with every reply). Hermes keeps no cost for a chat.
public struct ChatUsage: Equatable, Sendable {
    public struct Context: Equatable, Sendable {
        public let used: Int
        public let max: Int
        public let percent: Int
        /// Counted by Hermes rather than reported by the provider.
        public let estimated: Bool
    }

    /// `nil` before the first reply tells the gateway how full the context is.
    public let context: Context?
    public let input: Int
    public let output: Int
    public let calls: Int
    public let compressions: Int

    init?(_ json: JSONValue?) {
        guard let json, case .object = json else { return nil }
        func int(_ key: String) -> Int { json[key]?.intValue ?? 0 }
        let max = int("context_max")
        context =
            max > 0
            ? Context(
                used: int("context_used"), max: max, percent: int("context_percent"),
                estimated: json["context_estimated"]?.boolValue ?? false)
            : nil
        input = int("input")
        output = int("output")
        calls = int("calls")
        compressions = int("compressions")
    }

    init(context: Context?, input: Int = 0, output: Int = 0, calls: Int = 0, compressions: Int = 0) {
        self.context = context
        self.input = input
        self.output = output
        self.calls = calls
        self.compressions = compressions
    }
}

extension ChatThread {
    /// Asks the gateway how full this chat's context is. Keeps what's known if it can't answer.
    public func loadUsage() async {
        guard let sessionID, let channel = channel(),
            let result = try? await channel.call("session.usage", params: ["session_id": .string(sessionID)]),
            let usage = ChatUsage(result)
        else { return }
        self.usage = usage
    }

    /// Compression works between replies, one at a time.
    public var canCompress: Bool { canSend && !state.isRunning && !isCompressing }

    /// Summarises the older part of the conversation so the agent has room again. The transcript
    /// here stays as it is; a notice says what changed.
    public func compress() async {
        guard canCompress, let sessionID, let channel = channel() else { return }
        isCompressing = true
        defer { isCompressing = false }
        do {
            let result = try await channel.call(
                "session.compress", params: ["session_id": .string(sessionID)], timeout: .seconds(300))
            if let usage = ChatUsage(result["usage"]) { self.usage = usage }
            guard result["status"]?.stringValue == "compressed", (result["removed"]?.intValue ?? 0) > 0 else {
                state.addNotice(String(localized: "There was nothing to compress yet."))
                return
            }
            let before = result["before_tokens"]?.intValue ?? 0
            let after = result["after_tokens"]?.intValue ?? 0
            state.addNotice(
                String(
                    localized:
                        "Compressed the conversation from about \(Self.tokens(before)) to \(Self.tokens(after)) tokens."))
        } catch {
            state.addNotice(String(localized: "Couldn't compress: \(AppModel.describe(error))"))
        }
    }

    /// `12.3k`, `1.2M`: token counts for people.
    public nonisolated static func tokens(_ count: Int) -> String {
        switch count {
        case ..<1_000: "\(count)"
        case ..<1_000_000: (Double(count) / 1_000).formatted(.number.precision(.fractionLength(0...1))) + "k"
        default: (Double(count) / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "M"
        }
    }
}
