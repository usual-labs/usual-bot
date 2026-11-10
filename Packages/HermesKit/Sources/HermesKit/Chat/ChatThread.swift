import Foundation
import Observation
import os

/// One agent's chat: its transcript, whether a turn is running, what it needs from you,
/// and the actions you can take.
@MainActor
@Observable
public final class ChatThread {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    public let contactID: Contact.ID
    public internal(set) var state = ThreadState()
    public private(set) var phase: Phase = .loading
    /// Shown above the transcript, e.g. when older history couldn't be loaded.
    public private(set) var banner: String?
    /// Vault prompts waiting for you: unlock a password manager, save a login, enter a code.
    public internal(set) var vaultPrompts: [VaultPrompt] = []
    /// Commands waiting for your decision, oldest first.
    public private(set) var approvals: [ApprovalPrompt] = []
    /// Questions the agent asked through its clarify tool, waiting for your answers.
    public private(set) var questions: [ClarifyPrompt] = []
    /// Secrets and sudo passwords the gateway is waiting for. Never cached.
    public internal(set) var secrets: [SecretPrompt] = []
    /// Apps the agent asked to connect, while Hermes waits on them. Kept while offline, with its
    /// answers held back, as a sign-in may be under way in the browser.
    public internal(set) var connection: ConnectionCard?
    /// Agent replies since you last had this chat on screen.
    public internal(set) var unreadCount = 0
    /// Goes up each time the gateway's copy of the transcript replaces the one on screen. Item
    /// IDs count from the start of each copy, so a view keyed by them must start over with it.
    public private(set) var transcriptLoad = 0
    /// Attachments are on their way to the gateway; the message goes out once they're there.
    public private(set) var isUploading = false
    /// Images sent from this device in this run, by their path on the gateway, so your messages
    /// can show them. Not cached: after a relaunch they show by name.
    public private(set) var sentImages: [String: Data] = [:]
    /// Skills and commands this chat's `/` menu offers; loaded by `loadCommands()`.
    public internal(set) var commands: [SlashCommand] = []
    /// Text a command put back for you to edit and send (`/retry`); the message box takes it.
    public var prefill: String?
    /// The model this chat runs on; `nil` until the gateway says.
    public internal(set) var model: ChatModel?
    /// The models this chat can switch to; loaded by `loadModels()`.
    public internal(set) var modelProviders: [ModelProvider] = []
    /// Your last message is being taken back (`undo()`, `edit(_:)`).
    public internal(set) var isRewinding = false
    /// Questions asked on the side (`/btw`), oldest first, until you dismiss them.
    public internal(set) var sideQuestions: [SideQuestion] = []
    /// Tasks running on fresh agents in the background (`/bg`), oldest first.
    public internal(set) var backgroundTasks: [BackgroundTask] = []
    /// How full the context is and the tokens used; from `loadUsage()` and every reply.
    public internal(set) var usage: ChatUsage?
    /// `compress()` is running.
    public internal(set) var isCompressing = false
    /// Set by the app: whether vault secrets would cross the network unencrypted. Assumes so until told.
    var gatewayIsUnencrypted: @MainActor () -> Bool = { true }
    /// Set by the app: a background task finished, with its task and result (or failure).
    var backgroundTaskFinished: ((_ task: String, _ result: String) -> Void)?
    /// Set by the app: a reply or a request you aren't looking at.
    var alert: ((AgentAlert) -> Void)?
    /// Set by the app: a request alerted about is over, by its alert's ID.
    var alertWithdrawn: ((String) -> Void)?
    /// The requests already alerted about. The gateway sends waiting ones again on every attach.
    var announcedRequests: Set<String> = []
    /// Background tasks' answers, also kept apart from the transcript: the gateway's copy of the
    /// chat doesn't have them, so they're put back whenever it reloads. Newest last.
    var backgroundResults: [BackgroundResult] = []
    /// Set by the app: a background task's answer from its stored session, `nil` while it runs.
    var storedAnswer: ((_ taskID: String) async -> String?)?
    /// Set by the app: the gateway this chat is on.
    var gateway: (@MainActor () -> GatewayAddress?)?
    /// The gateway process's event numbering (`gateway.ready`'s `replay_epoch`); set by the app.
    var replayEpoch: String?
    /// The newest event seen from the live session, and the numbering it belongs to, so a short
    /// drop can be replayed (`ChatThread+Recovery.swift`).
    var lastSeq = 0
    var seqEpoch: String?
    /// The live session before the last drop.
    var lastSessionID: String?
    var recovery: Task<Void, Never>?
    /// Where the running turn began, when another device started it and this one hasn't seen
    /// what was asked.
    var elsewhereTurnStart: Int?

    /// The live session the gateway routes this chat's events to; `nil` while offline.
    private(set) var sessionID: String?
    /// The transcript holds the whole chat as the gateway last sent it, not the offline cache's
    /// last messages or an attach without the history (`historyOmitted`).
    var hasFullHistory = false
    /// The gateway attached without the history, as it was over its size limit.
    private(set) var historyOmitted = false
    /// When you last had this chat on screen, or read it on another device (`adoptRead(at:)`).
    /// Replies after it count as unread.
    var lastViewed: Date?
    /// How far the gateway knows this chat was read, on any device (`ReadSync`).
    var readOnGateway: Date?
    /// Set by the app: you've just seen this chat's replies so far, so the gateway can hear of it.
    var wasRead: (() -> Void)?
    /// Set by the app while this chat is on screen.
    var isVisible = false {
        didSet { if isVisible { markViewed() } }
    }

    private var openTask: Task<Void, Never>?
    /// The session of a chat moved here from another ID letting go of it, which opening waits for.
    var released: Task<Void, Never>?
    let channel: @MainActor () -> JSONRPCChannel?

    private static let log = Logger(subsystem: "UsualBot", category: "chat")

    init(contactID: Contact.ID, cached: CachedThread? = nil, channel: @escaping @MainActor () -> JSONRPCChannel?) {
        self.contactID = contactID
        self.channel = channel
        if let cached {
            // Show the last known transcript straight away; it is replaced once the gateway answers.
            state = cached.state
            lastViewed = cached.lastViewed
            unreadCount = cached.unreadCount
            sideQuestions = cached.sideQuestions ?? []
            backgroundTasks = cached.backgroundTasks ?? []
            backgroundResults = cached.backgroundResults ?? []
            phase = .ready
        }
    }

    /// Attached to the gateway, so messages can be sent.
    public var isAttached: Bool { sessionID != nil }

    /// What the sidebar shows for this agent.
    public var activity: Contact.Activity {
        if !approvals.isEmpty || !questions.isEmpty || !secrets.isEmpty || !vaultPrompts.isEmpty || connection != nil {
            return .needsYou
        }
        return state.isRunning ? .working : .idle
    }

    // MARK: - Attaching

    /// Finds or creates the agent's Bot Chat, loads its history and attaches to its events.
    /// Safe to call repeatedly; does nothing while attached or already opening.
    func open(knownID: String?, dialect: GatewayReady.Dialect) {
        guard sessionID == nil, openTask == nil else { return }
        guard let channel = channel() else { return }
        if case .failed = phase { phase = .loading }
        Self.log.notice("Opening chat \(self.contactID, privacy: .private)")
        openTask = Task {
            defer { openTask = nil }
            await released?.value
            released = nil
            do {
                let opened = try await BotChat.open(
                    profile: contactID, knownID: knownID, dialect: dialect, on: channel)
                attach(opened)
                Self.log.notice("Chat ready: \(opened.history.count, privacy: .public) messages")
            } catch {
                phase = .failed(AppModel.describe(error))
                Self.log.error("Chat open failed: \(AppModel.describe(error), privacy: .public)")
            }
        }
    }

    private func attach(_ opened: BotChat.Opened) {
        // The same live session with the same event numbering: what a short drop missed can be replayed.
        let epoch = opened.replayEpoch ?? replayEpoch
        let rejoined = opened.sessionID == lastSessionID && seqEpoch == epoch && lastSeq > 0
        if !rejoined { lastSeq = 0 }
        elsewhereTurnStart = nil
        sessionID = opened.sessionID
        lastSessionID = opened.sessionID
        seqEpoch = epoch
        model = ChatModel(info: opened.info) ?? model
        state = ThreadState(
            history: opened.history, running: opened.running, inflight: opened.inflight, kept: backgroundResults,
            todoState: opened.todoState)
        transcriptLoad += 1
        banner = opened.historyOmitted ? String(localized: "Earlier messages are too long to load here.") : nil
        historyOmitted = opened.historyOmitted
        hasFullHistory = !opened.historyOmitted
        // The gateway re-sends any question still waiting, so the list starts from its answer.
        adoptVaultPrompts(from: opened.openRequests)
        approvals = opened.openRequests.compactMap(ApprovalPrompt.init)
        questions = opened.openRequests.compactMap(ClarifyPrompt.init)
        secrets = opened.openRequests.compactMap(SecretPrompt.init)
        adoptConnection(opened.pendingConnection)
        announceRequests()
        if isVisible {
            markViewed()
        } else if let lastViewed {
            let since = lastViewed.timeIntervalSince1970
            let unreadBefore = unreadCount
            unreadCount = opened.history.filter { $0.role == "assistant" && ($0.timestamp ?? 0) > since }.count
            // A running turn alerts when it ends; its rows so far may not be the reply.
            if unreadCount > unreadBefore, !opened.running { announceReply(in: opened.history) }
        } else {
            // First time this device sees the chat: nothing is new yet.
            markViewed()
        }
        phase = .ready
        recoverMissed(rejoined: rejoined)
    }

    /// Shows the gateway's copy of the transcript in place of the one on screen.
    func replaceTranscript(with history: [HistoryMessage]) {
        state = ThreadState(history: history, running: false, kept: backgroundResults)
        transcriptLoad += 1
    }

    /// Ends this app's live session for a Bot renamed or deleted on the gateway, and forgets it.
    /// Hermes lets one live session hold a chat, so the old one would refuse the chat to the new ID
    /// ("open in another Hermes window"). `nil` when no session was attached.
    func release() -> Task<Void, Never>? {
        defer { detach() }
        guard let sessionID, let channel = channel() else { return nil }
        return Task { _ = try? await channel.call("session.close", params: ["session_id": .string(sessionID)]) }
    }

    /// Forgets the live session after the socket drops; the transcript stays on screen.
    /// The next `open` attaches again and reloads it, so nothing missed while offline is lost.
    func detach() {
        openTask?.cancel()
        openTask = nil
        recovery?.cancel()
        sessionID = nil
        vaultPrompts = []
        approvals = []
        questions = []
        secrets = []
    }

    // MARK: - Gateway traffic

    func apply(_ event: GatewayEvent) {
        if let seq = event.seq { lastSeq = max(lastSeq, seq) }
        if event.type == "session.replay_gap" {
            // This app fell too far behind, and the gateway stopped sending it the chat. The next
            // roster refresh attaches again and reloads it.
            detach()
            return
        }
        if event.type == "request.cancel" {
            withdraw(event.payload)
            announceRequests()
            return
        }
        if event.type == "session.info" {
            model = ChatModel(info: event.payload) ?? model
            return
        }
        if event.type == "connection.request" || event.type == "connection.update" {
            applyConnection(event)
            announceRequests()
            return
        }
        if event.type == "btw.complete" {
            receiveSideAnswer(event.payload)
            return
        }
        if event.type == "background.complete" {
            receiveBackgroundResult(event.payload)
            return
        }
        if event.type == "message.complete", let usage = ChatUsage(event.payload["usage"]) { self.usage = usage }
        // Sending from here marks the turn running before the gateway says it started. A turn
        // Hermes began itself brings its own line.
        if event.type == "message.start", !state.isRunning, event.payload["display_kind"] == nil {
            elsewhereTurnStart = state.items.count
        }
        let wasRunning = state.isRunning
        let itemsBefore = state.items.count
        state.apply(event)
        if event.type == "message.complete", wasRunning, !isVisible,
            let reply = state.items[min(itemsBefore, state.items.count)...].last(where: \.isReply)
        {
            unreadCount += 1
            announce(reply)
        }
        if event.type == "message.complete" { finishTurnElsewhere(event.payload) }
        if isVisible {
            lastViewed = Date()
            if event.type == "message.complete" { wasRead?() }
        }
    }

    func receive(_ approval: ApprovalPrompt) {
        guard !approvals.contains(where: { $0.id == approval.id }) else { return }
        approvals.append(approval)
    }

    func receive(_ prompt: ClarifyPrompt) {
        guard !questions.contains(where: { $0.id == prompt.id }) else { return }
        questions.append(prompt)
    }

    /// The gateway withdrew a request: answered elsewhere, timed out, or the turn ended.
    private func withdraw(_ payload: JSONValue) {
        guard let id = payload["id"]?.stringValue else { return }
        let timedOut = payload["reason"]?.stringValue == "timeout"
        if withdrawVaultPrompt(id, timedOut: timedOut) { return }
        if let index = approvals.firstIndex(where: { $0.id == id }) {
            let approval = approvals.remove(at: index)
            if timedOut {
                state.addNotice(String(localized: "Nobody answered in time, so “\(approval.shortCommand)” didn't run."))
            }
        } else if let index = questions.firstIndex(where: { $0.id == id }) {
            questions.remove(at: index)
            if timedOut { state.addNotice(String(localized: "The question timed out.")) }
        } else {
            _ = withdrawSecret(id, timedOut: timedOut)
        }
    }

    // MARK: - Your actions

    public var canSend: Bool { phase == .ready && sessionID != nil }

    /// Sends a message. While the agent works, the message steers the running turn instead.
    public func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
            if playsDemoReplies, canSend, !text.isEmpty, !state.isRunning {
                state.sendLocally(text)
                playDemoReply()
                return
            }
        #endif
        guard canSend, !text.isEmpty, let sessionID, let channel = channel() else { return }
        if let question = Self.sideQuestion(in: text) {
            askOnTheSide(question)
            return
        }
        if let task = Self.backgroundTask(in: text) {
            runInBackground(task)
            return
        }
        if text.split(separator: " ").first?.lowercased() == "/reasoning" {
            runReasoningCommand(text)
            return
        }
        if !state.isRunning, let command = command(in: text) {
            Task { await run(command, text: text, sessionID: sessionID, channel: channel) }
            return
        }
        if let prompt = questionTheBoxAnswers {
            answer(prompt, with: [prompt.questions[0].id: [text]])
            return
        }
        if state.isRunning {
            steer(text, sessionID: sessionID, channel: channel)
            return
        }
        state.sendLocally(text)
        Task { await submit(text, sessionID: sessionID, channel: channel) }
    }

    /// Uploads `attachments` to the chat, then sends them with `text`. Returns whether the message
    /// went out. On a failed upload nothing is sent, a notice says which file and why, and the
    /// caller keeps the draft. Attachments wait for the agent to finish: a running turn can't
    /// take them.
    public func send(_ text: String, attachments: [Attachment]) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else {
            guard canSend, !text.isEmpty else { return false }
            send(text)
            return true
        }
        guard canSendAttachments, let sessionID, let channel = channel() else { return false }
        isUploading = true
        defer { isUploading = false }
        var sent: [AttachmentRef] = []
        for attachment in attachments {
            do {
                sent.append(try await upload(attachment, sessionID: sessionID, channel: channel))
            } catch {
                // Images already queued would ride along with the next message: take them back.
                for ref in sent where ref.kind == .image {
                    _ = try? await channel.call(
                        "image.detach", params: ["session_id": .string(sessionID), "path": .string(ref.path)])
                }
                state.addNotice(String(localized: "Couldn't attach \(attachment.name): \(AppModel.describe(error))"))
                return false
            }
        }
        for (ref, attachment) in zip(sent, attachments) where ref.kind == .image {
            sentImages[ref.path] = attachment.data
        }
        // Queued images reach the agent with the turn; files only through their references.
        let files = sent.filter { $0.kind == .file }.map(\.line)
        let submitted = ([text] + files).filter { !$0.isEmpty }.joined(separator: "\n\n")
        state.sendLocally(
            ([text] + [sent.map(\.line).joined(separator: "\n")]).filter { !$0.isEmpty }
                .joined(separator: "\n\n"))
        await submit(submitted, sessionID: sessionID, channel: channel)
        return true
    }

    /// Whether `item` can take a reaction: a message in the store, or the newest of its kind, which
    /// the gateway finds without a row.
    public func canReact(to item: TranscriptItem) -> Bool {
        guard canSend, let role = Self.role(of: item) else { return false }
        return item.rowID != nil || state.items.last(where: { Self.role(of: $0) == role })?.id == item.id
    }

    /// Reacts to a message with `emoji`, or clears your reaction with `nil`. The same emoji again
    /// takes it back. Shows at once; a refusal puts the old reactions back with a notice.
    public func react(_ emoji: String?, to item: TranscriptItem) {
        guard canReact(to: item), let sessionID, let channel = channel(), let role = Self.role(of: item) else { return }
        let before = item.reactions
        state.setReactions(Reaction.toggling(emoji, in: before), on: item.id)
        var params: [String: JSONValue] = [
            "session_id": .string(sessionID), "emoji": emoji.map(JSONValue.string) ?? .null, "author": "user",
        ]
        if let rowID = item.rowID {
            params["row_id"] = .number(Double(rowID))
        } else {
            params["newest_role"] = .string(role)
        }
        Task {
            do {
                let result = try await channel.call("message.react", params: .object(params))
                state.setReactions(Reaction.list(result["reactions"]), rowID: result["row_id"]?.intValue, on: item.id)
            } catch {
                state.setReactions(before, on: item.id)
                state.addNotice(String(localized: "Couldn't react: \(AppModel.describe(error))"))
            }
        }
    }

    private static func role(of item: TranscriptItem) -> String? {
        switch item.content {
        case .user: "user"
        case .assistant: "assistant"
        default: nil
        }
    }

    /// Attachments go out only between turns, one message at a time.
    public var canSendAttachments: Bool { canSend && !state.isRunning && !isUploading }

    /// Sends one file to the gateway: an image into the next turn's queue, anything else into the
    /// chat's workspace. Larger files get longer, at roughly 100 KB/s at worst.
    private func upload(_ attachment: Attachment, sessionID: String, channel: JSONRPCChannel) async throws
        -> AttachmentRef
    {
        if attachment.isTooLarge { throw Attachment.TooLarge(limit: attachment.sizeLimit) }
        let timeout = Duration.seconds(30 + attachment.data.count / 100_000)
        let base64 = attachment.data.base64EncodedString()
        switch attachment.kind {
        case .image:
            let result = try await channel.call(
                "image.attach_bytes",
                params: [
                    "session_id": .string(sessionID), "content_base64": .string(base64),
                    "filename": .string(attachment.name),
                ], timeout: timeout)
            guard result["attached"]?.boolValue == true, let path = result["path"]?.stringValue else {
                throw GatewayError.invalidResponse
            }
            return AttachmentRef(kind: .image, path: path)
        case .file:
            let result = try await channel.call(
                "file.attach",
                params: [
                    "session_id": .string(sessionID), "name": .string(attachment.name),
                    "data_url": .string("data:application/octet-stream;base64," + base64),
                ], timeout: timeout)
            guard let line = result["ref_text"]?.stringValue, let ref = AttachmentRef(line: line) else {
                throw GatewayError.invalidResponse
            }
            return ref
        }
    }

    func submit(_ text: String, sessionID: String, channel: JSONRPCChannel, extra: [String: JSONValue] = [:]) async {
        do {
            let params = ["session_id": JSONValue.string(sessionID), "text": .string(text)].merging(extra) { $1 }
            _ = try await channel.call("prompt.submit", params: .object(params))
        } catch {
            state.addNotice(AppModel.describe(error))
            state.endTurnLocally()
        }
    }

    private func steer(_ text: String, sessionID: String, channel: JSONRPCChannel) {
        state.steerLocally(text)
        Task {
            do {
                let result = try await channel.call(
                    "session.steer", params: ["session_id": .string(sessionID), "text": .string(text)])
                switch result["status"]?.stringValue {
                case "rejected":
                    // The turn ended before the message arrived: send it as the next turn.
                    state.beginTurn()
                    await submit(text, sessionID: sessionID, channel: channel)
                case "unconfirmed":
                    // Sending it again could ask the agent twice.
                    state.addNotice(
                        String(
                            localized:
                                "Hermes couldn't confirm the agent took in your message. If the reply misses it, send it again."
                        ))
                default:
                    break
                }
            } catch {
                state.addNotice(AppModel.describe(error))
            }
        }
    }

    /// Asks the agent to stop the running turn. The gateway confirms with an "interrupted" reply.
    public func stop() {
        #if DEBUG
            // The demo's running reply has no gateway to interrupt it.
            if playsDemoReplies, state.isRunning, channel() == nil {
                apply(
                    GatewayEvent(
                        type: "message.complete", sessionID: "sample", seq: nil, payload: ["status": "interrupted"]))
                return
            }
        #endif
        guard state.isRunning, let sessionID, let channel = channel() else { return }
        Task {
            do {
                _ = try await channel.call("session.interrupt", params: ["session_id": .string(sessionID)])
            } catch {
                state.addNotice(AppModel.describe(error))
            }
        }
    }

    /// Answers an approval request.
    public func answer(_ approval: ApprovalPrompt, with choice: ApprovalPrompt.Choice) {
        guard let index = approvals.firstIndex(where: { $0.id == approval.id }), let channel = channel() else { return }
        approvals.remove(at: index)
        state.addNotice(Self.notice(for: choice, command: approval.shortCommand))
        Task { await channel.respond(to: approval.id, result: ["choice": .string(choice.rawValue)]) }
    }

    /// Answers the agent's questions. `picked` maps each question ID to the chosen or typed answers.
    public func answer(_ prompt: ClarifyPrompt, with picked: [String: [String]]) {
        guard let index = questions.firstIndex(where: { $0.id == prompt.id }), let channel = channel() else { return }
        questions.remove(at: index)
        var answers: [String: JSONValue] = [:]
        for question in prompt.questions {
            let values = picked[question.id] ?? []
            answers[question.id] = values.isEmpty ? .null : .string(ClarifyPrompt.encode(values, for: question))
        }
        state.steerLocally(Self.summary(of: prompt, picked: picked))
        Task {
            await channel.respond(to: prompt.id, result: ["answers": .object(answers), "outcome": "submitted"])
        }
    }

    /// Your answers as your side of the conversation. The card goes once answered, so with several
    /// questions each answer sits under its question; one answer reads as a plain reply.
    static func summary(of prompt: ClarifyPrompt, picked: [String: [String]]) -> String {
        let answered = prompt.questions.compactMap { question in
            picked[question.id]?.joined(separator: ", ").nonBlank.map { (question.text, $0) }
        }
        guard prompt.questions.count > 1 else { return answered.first?.1 ?? "" }
        return answered.map { "\($0.0)\n\($0.1)" }.joined(separator: "\n\n")
    }

    /// The question a message typed in the box answers, as in Grok ("Or answer in the chat below"):
    /// the only one waiting, asking one thing with one answer. Otherwise the card takes the answers,
    /// and a message steers the turn as usual.
    public var questionTheBoxAnswers: ClarifyPrompt? {
        guard questions.count == 1, let prompt = questions.first, prompt.questions.count == 1,
            !prompt.questions[0].allowsMultiple
        else { return nil }
        return prompt
    }

    /// Declines to answer; the agent carries on without the answers.
    public func skip(_ prompt: ClarifyPrompt) {
        guard let index = questions.firstIndex(where: { $0.id == prompt.id }), let channel = channel() else { return }
        questions.remove(at: index)
        state.addNotice(String(localized: "You skipped the question"))
        Task { await channel.respond(to: prompt.id, result: ["outcome": "cancelled"]) }
    }

    static func notice(for choice: ApprovalPrompt.Choice, command: String) -> String {
        switch choice {
        case .once: return String(localized: "You allowed “\(command)” once")
        case .session: return String(localized: "You allowed “\(command)” and commands like it in this chat")
        case .always: return String(localized: "You allowed “\(command)” and commands like it from now on")
        case .deny: return String(localized: "You denied “\(command)”")
        }
    }

    private func markViewed() {
        lastViewed = Date()
        unreadCount = 0
        wasRead?()
    }

    // MARK: - Offline cache

    var cacheEntry: CachedThread {
        CachedThread(
            state: state.trimmed(to: CachedThread.itemLimit), lastViewed: lastViewed, unreadCount: unreadCount,
            sideQuestions: sideQuestions, backgroundTasks: backgroundTasks,
            backgroundResults: Array(backgroundResults.suffix(20)))
    }

    #if DEBUG
        /// The demo: a sent message gets a scripted reply, as there's no gateway to answer it.
        var playsDemoReplies = false
        /// The demo: the history a chat holding only its last messages loads when search opens an
        /// older one (`loadDemoHistory()`).
        var demoFullHistory: [HistoryMessage]?

        /// The demo: a message with files shows as sent, as there's no gateway to upload them to.
        func sendDemo(_ text: String, attachments: [Attachment]) {
            let refs = attachments.map { AttachmentRef(kind: $0.kind, path: "/home/hermes/shared/" + $0.name) }
            for (ref, attachment) in zip(refs, attachments) where ref.kind == .image {
                sentImages[ref.path] = attachment.data
            }
            state.sendLocally(
                ([text] + [refs.map(\.line).joined(separator: "\n")]).filter { !$0.isEmpty }.joined(separator: "\n\n"))
            playDemoReply()
        }

        /// Tests and previews: a chat already open and showing `state`.
        static func sample(_ contactID: Contact.ID, state: ThreadState) -> ChatThread {
            let thread = ChatThread(contactID: contactID, channel: { nil })
            thread.state = state
            thread.sessionID = "sample"
            thread.hasFullHistory = true
            thread.gatewayIsUnencrypted = { false }
            thread.phase = .ready
            return thread
        }
    #endif
}
