import Foundation

extension ChatThread {
    /// Your newest message, the one Undo and Edit act on.
    public var lastSent: TranscriptItem? {
        state.items.last { if case .user = $0.content { true } else { false } }
    }

    /// Undo and Edit work between replies, one at a time.
    public var canRewind: Bool { canSend && !state.isRunning && !isUploading && !isRewinding && lastSent != nil }

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

    /// Replaces your last message with `text` and asks again: an undo, then a new message. If the
    /// undo fails, `text` goes back to the message box (`prefill`) rather than being lost.
    public func edit(_ text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard await undo() else {
            prefill = text
            return
        }
        send(text)
    }
}
