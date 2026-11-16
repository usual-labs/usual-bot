import Foundation

/// What an inline widget's `window.hermes.send(prompt)` resolves to, in the shape Hermes's desktop
/// app gives (`IntentAck` in `inline-preview-directive.tsx`), so a widget written for it works
/// here. `ok` means the gateway has the prompt, not that the agent has answered.
public struct WidgetAck: Equatable, Sendable {
    /// The desktop app's four reasons, the only values of `error`.
    public enum Failure: String, Sendable {
        case invalid
        case tooLong = "too_long"
        case throttled
        case undelivered
    }

    /// Why an `undelivered` prompt didn't go, which the desktop app doesn't say.
    public enum Reason: String, Sendable {
        /// The app isn't connected to the gateway.
        case offline
        /// A reply is running and the gateway (the dashboard) keeps no queue.
        case busy
        /// Widgets in rooms can't send.
        case room
        /// The gateway refused it.
        case refused
    }

    public let failure: Failure?
    public var reason: Reason?
    /// A sentence a widget can show.
    public var message: String?
    public var maxLength: Int?
    public var retryAfterMilliseconds: Int?

    public init(
        failure: Failure?, reason: Reason? = nil, message: String? = nil, maxLength: Int? = nil,
        retryAfterMilliseconds: Int? = nil
    ) {
        self.failure = failure
        self.reason = reason
        self.message = message
        self.maxLength = maxLength
        self.retryAfterMilliseconds = retryAfterMilliseconds
    }

    public var ok: Bool { failure == nil }

    public static let sent = WidgetAck(failure: nil)

    public static func undelivered(_ reason: Reason, _ message: String) -> WidgetAck {
        WidgetAck(failure: .undelivered, reason: reason, message: message)
    }

    /// What the page's promise resolves to.
    public var object: [String: Any] {
        var object: [String: Any] = ["ok": ok]
        if let failure { object["error"] = failure.rawValue }
        if let reason { object["reason"] = reason.rawValue }
        if let message { object["message"] = message }
        if let maxLength { object["maxLength"] = maxLength }
        if let retryAfterMilliseconds { object["retryAfterMs"] = retryAfterMilliseconds }
        return object
    }
}

/// The gate between a widget's page and the chat, as the desktop app's (`evaluateIntent`): an
/// accepted prompt becomes a turn the agent runs, so it's trimmed, never cut, and comes at most
/// once a second from one widget.
public enum WidgetIntent {
    /// A sentence, not a payload. Longer is refused: a cut prompt reaches the agent as nonsense
    /// while the widget thinks it went.
    public static let maxLength = 500
    /// Clicks are at human speed.
    public static let interval: Duration = .seconds(1)

    /// The prompt to send, or why not. `lastAccepted`: when this widget's previous prompt was let
    /// through.
    public static func evaluate(_ body: Any?, now: ContinuousClock.Instant, lastAccepted: ContinuousClock.Instant?)
        -> Result<String, WidgetIntentRefusal>
    {
        let prompt = (body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else { return .failure(WidgetIntentRefusal(ack: WidgetAck(failure: .invalid))) }
        guard prompt.count <= maxLength else {
            return .failure(WidgetIntentRefusal(ack: WidgetAck(failure: .tooLong, maxLength: maxLength)))
        }
        if let lastAccepted, now - lastAccepted < interval {
            let wait = interval - (now - lastAccepted)
            let milliseconds = Int(
                (Double(wait.components.seconds) * 1000 + Double(wait.components.attoseconds) / 1e15).rounded(.up))
            return .failure(
                WidgetIntentRefusal(ack: WidgetAck(failure: .throttled, retryAfterMilliseconds: max(1, milliseconds))))
        }
        return .success(prompt)
    }
}

public struct WidgetIntentRefusal: Error, Equatable {
    public let ack: WidgetAck
}
