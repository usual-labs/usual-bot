import Foundation

extension ChatThread {
    /// Your newest message, the one Undo and Edit act on.
    public var lastSent: TranscriptItem? {
        state.items.last { if case .user = $0.content { true } else { false } }
    }

    /// Why messages can't be edited, answered again or taken back right now, in words; `nil` when
    /// they can. The chat changes between replies, one change at a time.
    public var rewindUnavailable: String? {
        if !canSend { return String(localized: "Not connected to the gateway. Try again once it's back.") }
        // An approval or question belongs to a reply even when this device hasn't seen it start.
        if state.isRunning || !approvals.isEmpty || !questions.isEmpty {
            return activity == .needsYou
                ? String(localized: "The reply is waiting on you. Answer it or stop it first.")
                : String(localized: "Wait for the reply to end, or stop it.")
        }
        if isUploading || isRewinding { return String(localized: "Wait for the last change to finish.") }
        // Between two of a goal's replies, the next is about to start.
        if goalPhase == .working {
            return String(localized: "The goal's next reply is about to start. Stop the goal first.")
        }
        return nil
    }

    public var canRewind: Bool { rewindUnavailable == nil && lastSent != nil }

    /// The Bot's newest reply, when it answers your last message: the one Try Again is offered on.
    /// A reply to something Hermes delivered itself (a routine's result, another Bot's message)
    /// has no message of yours to ask again.
    public var retryReply: TranscriptItem? {
        guard let last = lastSent, let index = state.items.firstIndex(where: { $0.id == last.id }) else { return nil }
        let after = state.items[(index + 1)...]
        if after.contains(where: { if case .result = $0.content { true } else { false } }) { return nil }
        // Nor has a reply to one of a goal's own turns.
        if after.contains(where: { $0.content == .notice(GatewayTurn.goalStep) }) { return nil }
        return after.last { if case .assistant = $0.content { true } else { false } }
    }

    /// Why Try Again can't run, in words. Asking again sends the message's words, and a picture
    /// that went with it can't be sent a second time from here.
    public var tryAgainUnavailable: String? {
        if let reason = rewindUnavailable { return reason }
        guard let last = lastSent, case .user(let text) = last.content else { return nil }
        if AttachmentRef.split(text).attachments.contains(where: { $0.kind == .image }) {
            return String(localized: "Your message had a picture, which can't be sent again. Send it as a new message.")
        }
        return nil
    }

    /// What replacing `item` takes out of the chat with it.
    public struct RewindCost: Equatable, Sendable {
        /// Messages after it: replies, yours, and what Hermes delivered.
        public var messages = 0
        /// Those Hermes started itself: routine and background results, other Bots' messages.
        public var fromHermes = 0
        /// Steps the Bot took in them (commands, files, searches), which stay done.
        public var steps = 0
        /// More than the last exchange goes.
        public var reachesBack = false
        /// Worth asking first: more than the last exchange goes, or the Bot acted and that stays.
        public var needsConfirmation: Bool { reachesBack || steps > 0 }
    }

    /// `nil` for anything but a message of yours in this chat.
    public func rewindCost(of item: TranscriptItem) -> RewindCost? {
        guard case .user = item.content, let index = state.items.firstIndex(where: { $0.id == item.id }) else {
            return nil
        }
        var cost = RewindCost()
        for later in state.items[(index + 1)...] {
            switch later.content {
            case .user:
                cost.messages += 1
                cost.reachesBack = true
            case .result:
                cost.messages += 1
                cost.fromHermes += 1
                cost.reachesBack = true
            case .assistant, .member, .background, .output: cost.messages += 1
            case .activity(let steps): cost.steps += steps.count
            case .notice, .progress: break
            }
        }
        return cost
    }

    /// What Edit puts back in the message box: the text and any file references. Images went with
    /// the old message and would have to be attached again.
    public static func editableText(of item: TranscriptItem) -> String {
        guard case .user(let text) = item.content else { return "" }
        let split = AttachmentRef.split(text)
        let files = split.attachments.filter { $0.kind == .file }.map(\.line)
        return ([split.text] + files).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Takes back your last message and everything after it, on the gateway (so every attached
    /// app sees it) and here. Returns whether anything was removed.
    @discardableResult
    public func undo() async -> Bool {
        #if DEBUG
            if playsDemoReplies, canRewind, channel() == nil, let last = lastSent {
                state.rewind(from: last.id)
                return true
            }
        #endif
        guard canRewind, let sessionID, let channel = channel(), let last = lastSent else { return false }
        isRewinding = true
        defer { isRewinding = false }
        do {
            let result = try await channel.call("session.undo", params: ["session_id": .string(sessionID)])
            guard (result["removed"]?.intValue ?? 0) > 0 else {
                state.addNotice(String(localized: "There's nothing to undo."))
                return false
            }
        } catch {
            state.addNotice(String(localized: "Couldn't undo: \(AppModel.describe(error))"))
            return false
        }
        // The gateway's copy decides what's left; this device's guess stands in if it can't answer.
        let reloaded = try? await channel.call("session.history", params: ["session_id": .string(sessionID)])
        if let history = try? reloaded?["messages"]?.decode([HistoryMessage].self) {
            replaceTranscript(with: history)
        } else {
            state.rewind(from: last.id)
        }
        return true
    }

    /// Replaces a message of yours with `text` and asks again; everything after it goes. If
    /// nothing could be removed, `text` goes back to the message box (`prefill`) rather than being
    /// lost.
    public func edit(_ item: TranscriptItem, to text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard canRewind, case .user = item.content, state.items.contains(where: { $0.id == item.id }) else {
            prefill = text
            return
        }
        // Your last message goes the way Undo does, which every gateway has.
        if item.id == lastSent?.id {
            guard await undo() else {
                prefill = text
                return
            }
            send(text)
            return
        }
        #if DEBUG
            if playsDemoReplies, channel() == nil {
                state.rewind(from: item.id)
                send(text)
                return
            }
        #endif
        guard let sessionID, let channel = channel() else { return }
        // `send` would run these instead of sending them, after the chat was already cut.
        let firstWord = text.split(separator: " ").first.map { $0.lowercased() } ?? ""
        if command(in: text) != nil || ["/btw", "/bg", "/background", "/reasoning"].contains(firstWord) {
            state.addNotice(String(localized: "A command can't replace a message. Nothing was removed."))
            prefill = text
            return
        }
        isRewinding = true
        defer { isRewinding = false }
        guard let row = await row(of: item, sessionID: sessionID, channel: channel) else {
            state.addNotice(
                String(localized: "Couldn't find that message on the gateway, so nothing was removed. Try again."))
            prefill = text
            return
        }
        let before = state
        var params: [String: JSONValue] = [
            "session_id": .string(sessionID), "text": .string(text), "truncate_before_row_id": .number(Double(row)),
            // You were told what goes before this was sent (`RewindCost`).
            "confirm_truncate": true, "confirm_deep_truncate": true,
        ]
        if !before.items.prefix(while: { $0.id != item.id }).contains(where: \.isMessage) {
            params["confirm_empty_truncate"] = true
        }
        state.rewind(from: item.id)
        state.sendLocally(text)
        do {
            _ = try await channel.call("prompt.submit", params: .object(params))
        } catch {
            // The Webapp cuts and sends in two calls, so the cut may have happened: its copy decides.
            let reloaded = try? await channel.call("session.history", params: ["session_id": .string(sessionID)])
            if let history = try? reloaded?["messages"]?.decode([HistoryMessage].self) {
                replaceTranscript(with: history)
            } else {
                state = before
            }
            state.addNotice(String(localized: "Couldn't replace your message: \(Self.rewindRefusal(error))"))
            prefill = text
        }
    }

    /// Asks your last message again, for a fresh answer in place of the Bot's last one.
    public func tryAgain() async {
        guard tryAgainUnavailable == nil, retryReply != nil, let last = lastSent else { return }
        await edit(last, to: Self.editableText(of: last))
    }

    /// The gateway's row for `item`. Messages sent since the chat opened have none here, so the
    /// gateway's copy is read for them.
    private func row(of item: TranscriptItem, sessionID: String, channel: JSONRPCChannel) async -> Int? {
        if let row = item.rowID { return row }
        let reloaded = try? await channel.call("session.history", params: ["session_id": .string(sessionID)])
        guard let history = try? reloaded?["messages"]?.decode([HistoryMessage].self) else { return nil }
        return Self.row(of: item, in: state.items, stored: ThreadState(history: history, running: false).items)
    }

    /// Finds `item` in the gateway's copy by its words, counting from the newest among messages
    /// that say the same. This device's copy can hold lines the gateway's doesn't, such as your
    /// answer to a question, so position alone won't do. `nil` rather than a guess.
    static func row(of item: TranscriptItem, in items: [TranscriptItem], stored: [TranscriptItem]) -> Int? {
        func words(_ item: TranscriptItem) -> String? {
            guard case .user(let text) = item.content else { return nil }
            return AttachmentRef.split(text).text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let wanted = words(item), let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        let newer = items[(index + 1)...].filter { words($0) == wanted }.count
        let same = stored.filter { words($0) == wanted }
        // Unless both copies hold as many, the count could land on another message that says the
        // same, further back than the one you were shown.
        guard same.count == items.filter({ words($0) == wanted }).count, same.count > newer else { return nil }
        return same[same.count - 1 - newer].rowID
    }

    static func rewindRefusal(_ error: any Error) -> String {
        let reason = AppModel.describe(error)
        if reason.contains("compacted:") {
            return String(
                localized: "it was summarised when the chat was compressed, so the chat can't go back to it.")
        }
        if reason.contains("no longer in session history") {
            return String(localized: "it's no longer in the chat on the gateway.")
        }
        return reason
    }
}

extension TranscriptItem {
    /// Something said, rather than a step, a notice or a list.
    fileprivate var isMessage: Bool {
        switch content {
        case .user, .assistant, .member, .background, .output, .result: true
        case .activity, .notice, .progress: false
        }
    }
}
