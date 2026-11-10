import Foundation

/// A message waiting for the running reply to end, when it goes to the agent as a turn of its own.
public struct QueuedMessage: Identifiable, Equatable, Sendable, Codable {
    /// The ID it was submitted under, which the gateway lists it by (`input_id`).
    public let id: String
    public let text: String
    /// On this device only, and not sent until you say so: Stop took it back from the gateway, or
    /// the gateway couldn't be given it.
    public var isHeld = false
    /// The gateway's own name for it, once the gateway has it.
    var admissionID: String?

    /// On its way to the gateway: there's nothing to take back yet.
    public var isSending: Bool { !isHeld && admissionID == nil }
}

/// The queue is the gateway's own (Hermes keeps one per chat and the official app shows the same
/// one), so a queued message goes out even with this app closed. Everything you can do to a queued
/// message starts by taking it back with `prompt.cancel`; see `docs/agents/canonical-protocol.md`.
extension ChatThread {
    /// A message can wait for the running reply to end. Only the gateway's own listener keeps a
    /// queue that can be listed and taken back; the dashboard's can't, so there's no queue there.
    public var canQueue: Bool { canSend && state.isRunning && (queuesOnGateway || isDemo) }

    /// Whether any queued message is held on this device.
    public var holdsQueue: Bool { queue.contains(where: \.isHeld) }

    private var isDemo: Bool {
        #if DEBUG
            playsDemoReplies && channel() == nil
        #else
            false
        #endif
    }

    // MARK: - Your actions

    /// Queues `text` behind the running reply. With nothing running, or for a command, it's sent
    /// as usual: commands run when you send them.
    public func enqueue(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canQueue, !text.isEmpty, !text.hasPrefix("/") else { return send(text) }
        let item = QueuedMessage(id: UUID().uuidString, text: text, admissionID: isDemo ? "demo" : nil)
        queue.append(item)
        if !isDemo { Task { await admit(item) } }
    }

    /// Sends a queued message at once: into the running reply as a steer, or as the next message
    /// when nothing runs.
    public func sendNow(_ item: QueuedMessage) {
        guard canSend, queue.contains(item) else { return }
        Task {
            guard await takeBack(item) else { return }
            send(item.text)
        }
    }

    /// Takes a queued message out of the queue and puts its text in the message box.
    public func edit(_ item: QueuedMessage) {
        guard queue.contains(item) else { return }
        Task {
            guard await takeBack(item) else { return }
            prefill = item.text
        }
    }

    public func remove(_ item: QueuedMessage) {
        guard queue.contains(item) else { return }
        Task { _ = await takeBack(item) }
    }

    /// Queues the held messages again, in order. With nothing running the first starts at once.
    public func resumeQueue() {
        guard canSend else { return }
        let held = queue.filter(\.isHeld)
        for item in held {
            guard let index = queue.firstIndex(of: item) else { continue }
            queue[index].isHeld = false
        }
        #if DEBUG
            if isDemo {
                for index in queue.indices { queue[index].admissionID = "demo" }
                if !state.isRunning { startNextDemoQueued() }
                return
            }
        #endif
        // One at a time, so the gateway queues them in this order.
        Task { for item in held { await admit(item) } }
    }

    // MARK: - The gateway's queue

    /// Gives a queued message to the gateway, which sends it when the turns before it end. A
    /// failure holds it here under the same ID: the gateway answers a second try of an ID it did
    /// take with the first one's receipt, so trying again can't send the message twice.
    private func admit(_ item: QueuedMessage) async {
        do {
            guard let sessionID = liveSessionID, let channel = channel() else { throw GatewayError.disconnected }
            let receipt = try await channel.call(
                "prompt.submit",
                params: [
                    "session_id": .string(sessionID), "text": .string(item.text), "submission_id": .string(item.id),
                ]
            )
            guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return }
            switch receipt["status"]?.stringValue {
            case "started": began(item.id)
            // An earlier try that didn't hear back had gone out after all.
            case "terminal": queue.remove(at: index)
            default: queue[index].admissionID = receipt["admission_id"]?.stringValue
            }
        } catch {
            guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return }
            queue[index].isHeld = true
            queue[index].admissionID = nil
            state.addNotice(
                String(localized: "Couldn't queue your message, so it's held here: \(AppModel.describe(error))"))
        }
    }

    /// Takes a message out of the queue: off the gateway with `prompt.cancel`, or off this device
    /// when it's held. `false` when it's still there or had already started. The gateway stops a
    /// started one in the same call, so the message then shows as sent, with a notice unless `quiet`.
    private func takeBack(_ item: QueuedMessage, quiet: Bool = false) async -> Bool {
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return false }
        guard !item.isHeld, !isDemo else {
            queue.remove(at: index)
            return true
        }
        guard let admission = item.admissionID, let sessionID = liveSessionID, let channel = channel() else {
            return false
        }
        // The gateway's lists leave it out from here on, so it doesn't come back while this runs.
        takenBack.insert(item.id)
        queue.remove(at: index)
        do {
            let receipt = try await channel.call(
                "prompt.cancel", params: ["session_id": .string(sessionID), "admission_id": .string(admission)])
            if receipt["status"] == "terminal", receipt["outcome"] == "cancelled" { return true }
            show(started: item.text)
            if !quiet {
                state.addNotice(String(localized: "That message had already started, so its reply was stopped."))
            }
        } catch {
            takenBack.remove(item.id)
            queue.insert(item, at: min(index, queue.count))
            state.addNotice(String(localized: "Couldn't take your queued message back: \(AppModel.describe(error))"))
        }
        return false
    }

    /// Before Stop: the gateway would start the next queued message the moment the reply stops,
    /// so they come back first and are held here until you resume them.
    func holdQueue() async {
        for item in queue where !item.isHeld && !item.isSending {
            if isDemo {
                if let index = queue.firstIndex(of: item) { queue[index].isHeld = true }
            } else if await takeBack(item, quiet: true) {
                // A new ID: the gateway knows the old one as cancelled.
                queue.append(QueuedMessage(id: UUID().uuidString, text: item.text, isHeld: true))
            }
        }
    }

    /// Reads the gateway's list of what's waiting and running (`pending`, in an attach's snapshot
    /// and every `session.info` about the queue). `attaching`: the snapshot already shows the
    /// running turn's message.
    func adoptQueue(from info: JSONValue?, attaching: Bool = false) {
        guard case .array(let rows) = info?["pending"] else { return }
        let running = info?["running"]?.boolValue ?? state.isRunning
        var waiting: [QueuedMessage] = []
        for row in rows {
            // A message being steered into the reply is listed as started; it isn't a turn.
            guard let id = row["input_id"]?.stringValue, let text = row["text"]?.stringValue,
                !sentDirectly.contains(id), !takenBack.contains(id), row["steering"]?.boolValue != true
            else { continue }
            let mine = queue.contains { $0.id == id }
            switch row["status"]?.stringValue {
            case "queued":
                // Another app's: only what the gateway offers queue controls for (typed messages,
                // not a routine's result), and only behind a reply. Anything sent to an idle chat
                // is listed as queued for a moment before it starts.
                guard mine || (running && !CanonicalProtocol.rows(row["controls"]).isEmpty) else { continue }
                waiting.append(QueuedMessage(id: id, text: text, admissionID: row["admission_id"]?.stringValue))
            case "started" where mine:
                if attaching { queue.removeAll { $0.id == id } } else { began(id) }
            default:
                break
            }
        }
        // Held ones first: they're older. One not listed any more has gone out or been taken back,
        // unless the gateway hasn't answered for it yet.
        let listed = Set(waiting.map(\.id))
        queue =
            queue.filter { $0.isHeld && !listed.contains($0.id) } + waiting
            + queue.filter { $0.isSending && !listed.contains($0.id) }
    }

    /// A queued message's turn began: it leaves the queue and shows as sent.
    private func began(_ id: String) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        show(started: queue.remove(at: index).text)
    }

    private func show(started text: String) {
        if let start = elsewhereTurnStart {
            // `message.start` came first and marked where the turn begins.
            elsewhereTurnStart = nil
            state.insertPrompt(HistoryMessage(role: "user", text: text), at: start)
        } else if state.isRunning {
            state.steerLocally(text)
        } else {
            state.sendLocally(text)
        }
    }

    #if DEBUG
        /// The demo has no gateway to send the next queued message when a reply ends.
        func startNextDemoQueued() {
            guard isDemo, !state.isRunning, let index = queue.firstIndex(where: { !$0.isHeld }) else { return }
            state.sendLocally(queue.remove(at: index).text)
            playDemoReply()
        }
    #endif
}
