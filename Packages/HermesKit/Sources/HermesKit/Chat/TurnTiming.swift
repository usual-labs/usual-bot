import Foundation

/// A turn's steps on this device, for `Trace`: sent, taken, started, first words, ended.
///
/// `origin` is `here` for a message sent from this device, `elsewhere` for one another of your
/// devices sent (its submission ID shows once the gateway's queue names it, `turn.elsewhere`), and
/// `hermes` for one Hermes started itself. Grep both devices' logs for the ID to follow one
/// message across them; the chat is the same `Trace.tag` on each.
struct TurnTiming {
    // A new value starts over: the thread makes one when its link drops.
    private var submittedAt: ContinuousClock.Instant?
    private var startedAt: ContinuousClock.Instant?
    private var origin = "here"
    private var sawText = false

    /// A message went to the gateway as a turn.
    mutating func submitted(_ id: String?, chat: Contact.ID, bytes: Int) {
        submittedAt = .now
        Trace.event(
            "turn.submit", Trace.fields("chat=\(Trace.tag(chat))", id.map { "id=\($0)" } ?? "", "bytes=\(bytes)"))
    }

    /// The gateway answered the submit.
    func accepted(_ id: String?, chat: Contact.ID, error: (any Error)?) {
        Trace.event(
            "turn.accepted",
            Trace.fields(
                "chat=\(Trace.tag(chat))", id.map { "id=\($0)" } ?? "", Trace.since(submittedAt),
                error.map { "error=\(Trace.reason($0))" } ?? "ok"))
    }

    /// Before the thread applies `event`. `runningHere`: this device already showed the turn
    /// running, as it does for what it sends.
    mutating func observe(_ event: GatewayEvent, chat: Contact.ID, runningHere: Bool) {
        let tag = Trace.tag(chat)
        switch event.type {
        case "message.start":
            guard startedAt == nil else { return }
            origin = runningHere ? "here" : event.payload["display_kind"] == nil ? "elsewhere" : "hermes"
            startedAt = .now
            sawText = false
            Trace.event(
                "turn.start",
                Trace.fields("chat=\(tag)", "origin=\(origin)", Trace.since(submittedAt, "since_submit_ms")))
        case "message.delta" where !sawText && startedAt != nil:
            sawText = true
            Trace.event(
                "turn.first_text",
                Trace.fields(
                    "chat=\(tag)", "origin=\(origin)", Trace.since(startedAt),
                    Trace.since(submittedAt, "since_submit_ms")))
        case "message.complete":
            guard let startedAt else { return }
            let status = event.payload["status"]?.stringValue ?? event.payload["outcome"]?.stringValue ?? "complete"
            Trace.event(
                "turn.complete",
                Trace.fields(
                    "chat=\(tag)", "origin=\(origin)", "status=\(status)", Trace.since(startedAt),
                    Trace.since(submittedAt, "since_submit_ms")))
            self.startedAt = nil
            submittedAt = nil
        default:
            break
        }
    }

    /// Another device's message showed here from the gateway's queue.
    func shownElsewhere(_ id: String, chat: Contact.ID) {
        Trace.event("turn.elsewhere", Trace.fields("chat=\(Trace.tag(chat))", "id=\(id)", Trace.since(startedAt)))
    }
}
