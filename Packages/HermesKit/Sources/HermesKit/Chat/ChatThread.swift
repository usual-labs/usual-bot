import Foundation
import Observation
import os

/// One agent's chat: its transcript, whether a turn is running, and the actions you can take.
@MainActor
@Observable
public final class ChatThread {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    public let contactID: Contact.ID
    public private(set) var state = ThreadState()
    public private(set) var phase: Phase = .loading
    /// Shown above the transcript, e.g. when older history couldn't be loaded.
    public private(set) var banner: String?

    /// The live session the gateway routes this chat's events to.
    private(set) var sessionID: String?
    private var openTask: Task<Void, Never>?
    private let channel: @MainActor () -> JSONRPCChannel?

    private static let log = Logger(subsystem: "UsualBot", category: "chat")

    init(contactID: Contact.ID, channel: @escaping @MainActor () -> JSONRPCChannel?) {
        self.contactID = contactID
        self.channel = channel
    }

    /// Finds or creates the agent's Bot Chat and loads its history. Safe to call repeatedly.
    func open(knownID: String?, dialect: GatewayReady.Dialect) {
        guard sessionID == nil, openTask == nil else { return }
        guard dialect == .legacy else {
            phase = .failed(String(localized: "Chat on this gateway's newer protocol isn't supported yet."))
            return
        }
        guard let channel = channel() else {
            Self.log.notice("Chat open deferred: gateway offline")
            return
        }
        if case .failed = phase { phase = .loading }
        Self.log.notice("Opening chat \(self.contactID, privacy: .private)")
        openTask = Task {
            defer { openTask = nil }
            do {
                let opened = try await BotChat.open(profile: contactID, knownID: knownID, on: channel)
                sessionID = opened.sessionID
                state = ThreadState(history: opened.history, running: opened.running)
                banner = opened.historyOmitted ? String(localized: "Earlier messages are too long to load here.") : nil
                phase = .ready
                Self.log.notice(
                    "Chat ready: \(opened.history.count, privacy: .public) messages, \(self.state.items.count, privacy: .public) items"
                )
            } catch {
                phase = .failed(AppModel.describe(error))
                Self.log.error("Chat open failed: \(AppModel.describe(error), privacy: .public)")
            }
        }
    }

    /// Forgets the live session; the next `open` attaches again (after a reconnect).
    func detach() {
        openTask?.cancel()
        openTask = nil
        sessionID = nil
        if case .ready = phase { return }
        phase = .loading
    }

    func apply(_ event: GatewayEvent) {
        state.apply(event)
    }

    #if DEBUG
        /// Tests and previews: a chat already open and showing `state`.
        static func sample(_ contactID: Contact.ID, state: ThreadState) -> ChatThread {
            let thread = ChatThread(contactID: contactID, channel: { nil })
            thread.state = state
            thread.sessionID = "sample"
            thread.phase = .ready
            return thread
        }
    #endif

    public var canSend: Bool { phase == .ready && sessionID != nil && !state.isRunning }

    /// Sends a message to the agent.
    public func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty, let sessionID, let channel = channel() else { return }
        state.sendLocally(text)
        Task {
            do {
                _ = try await channel.call(
                    "prompt.submit", params: ["session_id": .string(sessionID), "text": .string(text)])
            } catch {
                state.addNotice(AppModel.describe(error))
                state.endTurnLocally()
            }
        }
    }

    /// Asks the agent to stop the running turn. The gateway confirms with an "interrupted" reply.
    public func stop() {
        guard state.isRunning, let sessionID, let channel = channel() else { return }
        Task {
            do {
                _ = try await channel.call("session.interrupt", params: ["session_id": .string(sessionID)])
            } catch {
                state.addNotice(AppModel.describe(error))
            }
        }
    }
}
