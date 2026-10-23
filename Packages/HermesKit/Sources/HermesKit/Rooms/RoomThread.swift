import CryptoKit
import Foundation
import Observation
import os

/// One room: its transcript, who is answering, the approvals its agents wait on, and sending.
///
/// Rooms push nothing, so the room is read by polling: `sync()` reads the log after the last
/// event it has, then the room's status. The room view calls it every 2 s while it's on screen,
/// and the app calls it when the room list shows new events.
@MainActor
@Observable
public final class RoomThread {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    public let roomID: String
    public private(set) var name: String
    public private(set) var state: RoomState
    public private(set) var phase: Phase = .loading
    /// Members answering right now, when the gateway names them (Hermes 0.22.4 and later).
    public private(set) var working: Set<String> = []
    /// Whether any agent is answering; older gateways report only this, not who.
    public private(set) var isBusy = false
    /// Commands the room's agents wait on, with who asked.
    public private(set) var approvals: [RoomApproval] = []
    /// Your messages sent but not yet back in the log.
    public private(set) var pending: [PendingMessage] = []
    /// Member replies since you last had the room on screen.
    public private(set) var unreadCount = 0
    /// Whether the gateway's room service is running; rooms can't be used without it.
    public private(set) var driverRunning = true

    var isVisible = false {
        didSet { if isVisible { markViewed() } }
    }

    private var lastViewed: Date?
    private var syncing = false
    private let channel: @MainActor () -> JSONRPCChannel?

    private static let log = Logger(subsystem: "UsualBot", category: "rooms")

    init(summary: RoomSummary, channel: @escaping @MainActor () -> JSONRPCChannel?) {
        roomID = summary.id
        name = summary.name
        state = RoomState(members: summary.members)
        self.channel = channel
    }

    public struct PendingMessage: Identifiable, Equatable, Sendable {
        public let id: String
        public let text: String
        /// The log event ID the gateway gives it: `user:` + SHA-256 of the client's event ID.
        let eventID: String
    }

    /// The last event applied; the roster compares it with the room's newest.
    var cursor: Int { state.cursor }

    public var activity: Contact.Activity {
        if !approvals.isEmpty { return .needsYou }
        return isBusy || !pending.isEmpty ? .working : .idle
    }

    /// The newest message, for the sidebar.
    public var preview: String? {
        for item in state.items.reversed() {
            switch item.content {
            case .user(let text): return text
            case .member(let id, let text): return "\(state.name(id)): \(text)"
            default: continue
            }
        }
        return nil
    }

    func update(_ summary: RoomSummary) {
        name = summary.name
    }

    // MARK: - Reading

    /// Reads new events and the room's status. Safe to call often; overlapping calls are skipped.
    public func sync() async {
        guard !syncing, let channel = channel() else { return }
        syncing = true
        defer { syncing = false }
        do {
            var hasMore = true
            var newReplies = 0
            while hasMore {
                let page = try await channel.call(
                    "groups.log",
                    params: ["room_id": .string(roomID), "since_seq": .number(Double(cursor)), "limit": 200])
                var events: [RoomEvent] = []
                if case .array(let raw) = page["events"] { events = raw.compactMap(RoomEvent.init) }
                newReplies += events.filter { $0.kind == "message.member" && isNew($0) }.count
                state.apply(events)
                hasMore = page["has_more"]?.boolValue == true && !events.isEmpty
            }
            pending.removeAll { state.seenEventIDs.contains($0.eventID) }
            if phase == .ready, !isVisible { unreadCount += newReplies }
            // The first load sets the baseline: replies from before this device saw the room aren't new.
            if isVisible || lastViewed == nil { markViewed() }
            try await readStatus(on: channel)
            phase = .ready
        } catch {
            if phase != .ready { phase = .failed(AppModel.describe(error)) }
            Self.log.error("Room sync failed: \(AppModel.describe(error), privacy: .public)")
        }
    }

    /// A reply counts as unread when it arrived after you last looked; the first load of a room
    /// this device never showed counts nothing.
    private func isNew(_ event: RoomEvent) -> Bool {
        guard let lastViewed else { return false }
        return event.createdAt > lastViewed
    }

    private func readStatus(on channel: JSONRPCChannel) async throws {
        let result = try await channel.call("groups.state", params: ["room_id": .string(roomID)])
        if let room = result["room"], case .array(let raw) = room["members"] {
            let members = raw.compactMap(RoomMember.init)
            if !members.isEmpty, members != state.members { state.replaceMembers(members) }
        }
        // The gateway leaves the status out when its room service isn't running.
        guard let status = result["driver_status"] else {
            driverRunning = false
            working = []
            isBusy = false
            approvals = []
            return
        }
        driverRunning = status["running"]?.boolValue ?? true
        // Queued turns wait behind another; only running ones are replying.
        if case .array(let activity) = status["member_activity"] {
            working = Set(
                activity.filter { $0["status"]?.stringValue != "queued" }.compactMap { $0["member_id"]?.stringValue })
        } else {
            working = []
        }
        isBusy = !working.isEmpty || status["working"]?.boolValue == true
        if case .array(let actions) = status["pending_actions"] {
            approvals = actions.compactMap(RoomApproval.init)
        } else {
            approvals = []
        }
    }

    // MARK: - Your actions

    public var canSend: Bool { phase == .ready && driverRunning && channel() != nil }

    /// Sends a message to the room. Without @mentions every member answers; with them, only
    /// those named.
    public func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty, let channel = channel() else { return }
        let clientID = UUID().uuidString.lowercased()
        let message = PendingMessage(id: clientID, text: text, eventID: Self.userEventID(clientID))
        pending.append(message)
        Task {
            do {
                _ = try await channel.call(
                    "groups.send",
                    params: [
                        "room_id": .string(roomID), "event_id": .string(clientID),
                        "payload": ["text": .string(text), "thread_id": .string(clientID)],
                    ])
                await sync()
            } catch {
                pending.removeAll { $0.id == clientID }
                state.addNotice(String(localized: "Your message didn't send: \(AppModel.describe(error))"))
            }
        }
    }

    /// Asks every agent in the room to stop.
    public func stop() {
        guard let channel = channel() else { return }
        Task {
            do {
                _ = try await channel.call(
                    "groups.stop",
                    params: ["room_id": .string(roomID), "cancel_id": .string("usualbot-\(UUID().uuidString)")])
                await sync()
            } catch {
                state.addNotice(AppModel.describe(error))
            }
        }
    }

    /// Answers an agent's approval request. Rooms offer only "once" and "deny".
    public func answer(_ approval: RoomApproval, with choice: ApprovalPrompt.Choice) {
        guard let channel = channel() else { return }
        approvals.removeAll { $0.id == approval.id }
        let command = approval.prompt.shortCommand
        state.addNotice(ChatThread.notice(for: choice, command: command))
        Task {
            do {
                _ = try await channel.call(
                    "groups.approve",
                    params: [
                        "room_id": .string(roomID), "member_id": .string(approval.memberID),
                        "task_id": .string(approval.taskID),
                        "execution_generation": .number(Double(approval.executionGeneration)),
                        "choice": .string(choice.rawValue), "request_id": .string(approval.prompt.id),
                    ])
            } catch {
                state.addNotice(AppModel.describe(error))
            }
            await sync()
        }
    }

    /// Creates a room seating `profiles`, two to six agents on this gateway, and returns it as
    /// the room list would show it.
    static func create(named name: String, profiles: [String], on channel: JSONRPCChannel) async throws -> RoomSummary {
        // Seated as the official app seats them: you @mention each agent by its profile name.
        let members: [JSONValue] = profiles.map { profile in
            let profile = JSONValue.string(profile)
            return [
                "member_id": profile, "profile": profile, "handle": profile,
                "target": ["kind": "local", "profile": profile],
            ]
        }
        let result = try await channel.call(
            "groups.create",
            params: [
                "room_id": .string(UUID().uuidString.lowercased()),
                "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "members": .array(members),
            ])
        guard let row = result["room"], let summary = RoomSummary(row) else { throw GatewayError.invalidResponse }
        return summary
    }

    private func markViewed() {
        lastViewed = Date()
        unreadCount = 0
    }

    /// The gateway files a user message under `user:` + SHA-256 of the client's event ID.
    nonisolated static func userEventID(_ clientID: String) -> String {
        let digest = SHA256.hash(data: Data(clientID.utf8))
        return "user:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    #if DEBUG
        /// Tests and previews: a room already showing `events`.
        static func sample(_ summary: RoomSummary, events: [JSONValue]) -> RoomThread {
            let room = RoomThread(summary: summary, channel: { nil })
            room.state.apply(events.compactMap(RoomEvent.init))
            room.phase = .ready
            return room
        }
    #endif
}

/// A room agent waiting for your OK on a command (`groups.state` → `pending_actions`).
public struct RoomApproval: Identifiable, Equatable, Sendable {
    public var id: String { prompt.id }
    public let memberID: String
    let taskID: String
    let executionGeneration: Int
    public let prompt: ApprovalPrompt

    init?(_ action: JSONValue) {
        guard action["kind"]?.stringValue == "approval",
            let memberID = action["member_id"]?.stringValue,
            let taskID = action["task_id"]?.stringValue,
            let generation = action["execution_generation"]?.intValue,
            let requestID = action["request_id"]?.stringValue ?? action["approval"]?["request_id"]?.stringValue
        else { return nil }
        self.memberID = memberID
        self.taskID = taskID
        executionGeneration = generation
        let approval = action["approval"] ?? .null
        // The room service only accepts "once" and "deny".
        var choices: [ApprovalPrompt.Choice] = []
        if case .array(let offered) = approval["choices"] {
            choices = offered.compactMap { $0.stringValue.flatMap(ApprovalPrompt.Choice.init(rawValue:)) }
                .filter { $0 == .once || $0 == .deny }
        }
        prompt = ApprovalPrompt(
            id: requestID, sessionID: action["session_id"]?.stringValue ?? "",
            command: approval["command"]?.stringValue ?? "", description: approval["description"]?.stringValue ?? "",
            choices: choices.isEmpty ? [.once, .deny] : choices)
    }
}
