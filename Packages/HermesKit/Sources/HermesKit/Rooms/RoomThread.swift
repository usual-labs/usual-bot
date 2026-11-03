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
    /// Turns that stopped partway and can be run again, by task ID.
    public private(set) var retries: [String] = []
    /// Whose turn each retry is, where that could be told (`retryMember`).
    private var retryMembers: [String: String] = [:]
    /// Members with a turn running or queued at the last read.
    private var lastLive: Set<String> = []
    /// Your messages sent but not yet back in the log.
    public private(set) var pending: [PendingMessage] = []
    /// A message that didn't send, for the message box to take back so its text isn't lost.
    public var unsent: String?
    /// Member replies since you last had the room on screen.
    public private(set) var unreadCount = 0
    /// Whether the gateway's room service is running; rooms can't be used without it.
    public private(set) var driverRunning = true

    var isVisible = false {
        didSet { if isVisible { markViewed() } }
    }
    /// Set by the app: a reply or a request you aren't looking at.
    var alert: ((AgentAlert) -> Void)?
    /// Set by the app: a request alerted about is over, by its alert's ID.
    var alertWithdrawn: ((String) -> Void)?

    private var lastViewed: Date?
    private var syncing = false
    private var announcedRequests: Set<String> = []
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
        if !approvals.isEmpty || !retries.isEmpty { return .needsYou }
        return isBusy || !pending.isEmpty ? .working : .idle
    }

    /// The newest message, for the sidebar.
    public var preview: String? {
        for item in state.items.reversed() {
            switch item.content {
            case .user(let text): return Self.readable(text)
            case .member(let id, let text): return "\(state.name(id)): \(Self.readable(text))"
            default: continue
            }
        }
        return nil
    }

    /// A message as one plain line, without its `MEDIA:` and attachment lines.
    nonisolated static func readable(_ text: String) -> String {
        MessageSearch.plain(text).nonBlank ?? String(localized: "Sent a file")
    }

    func update(_ summary: RoomSummary) {
        name = summary.name
    }

    func adoptName(_ name: String) {
        self.name = name
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
            if phase == .ready, !isVisible, newReplies > 0 {
                unreadCount += newReplies
                announceNewestReply()
            }
            // The first load sets the baseline: replies from before this device saw the room aren't new.
            if isVisible || lastViewed == nil { markViewed() }
            try await readStatus(on: channel)
            announceRequests()
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

    private func announceNewestReply() {
        for item in state.items.reversed() {
            guard case .member(let id, let text) = item.content else { continue }
            alert?(AgentAlert(id: UUID().uuidString, kind: .message, subtitle: state.name(id), preview: text))
            return
        }
    }

    /// Alerts about what's newly waiting on you, and takes back what no longer is.
    private func announceRequests() {
        let waiting =
            approvals.map { approval in
                (
                    id: approval.id,
                    text: String(
                        localized: "\(state.name(approval.memberID)) wants to run “\(approval.prompt.shortCommand)”")
                )
            }
            + retries.map { taskID in
                (
                    id: taskID,
                    text: retryMember(taskID).map {
                        String(localized: "\(state.name($0))'s reply stopped partway. Open the room to try again.")
                    } ?? String(localized: "A reply stopped partway. Open the room to try again.")
                )
            }
        for request in waiting where !announcedRequests.contains(request.id) && !isVisible {
            alert?(AgentAlert(id: request.id, kind: .needsYou, subtitle: nil, preview: request.text))
        }
        let ids = Set(waiting.map(\.id))
        for id in announcedRequests.subtracting(ids) { alertWithdrawn?(id) }
        announcedRequests = ids
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
            retries = []
            retryMembers = [:]
            lastLive = []
            return
        }
        driverRunning = status["running"]?.boolValue ?? true
        // Queued turns wait behind another; only running ones are replying.
        var live: Set<String> = []
        if case .array(let activity) = status["member_activity"] {
            working = Set(
                activity.filter { $0["status"]?.stringValue != "queued" }.compactMap { $0["member_id"]?.stringValue })
            live = Set(activity.compactMap { $0["member_id"]?.stringValue })
        } else {
            working = []
        }
        isBusy = !working.isEmpty || status["working"]?.boolValue == true
        let earlier = Set(retries)
        if case .array(let actions) = status["pending_actions"] {
            approvals = actions.compactMap(RoomApproval.init)
            retries = actions.filter { $0["kind"]?.stringValue == "retry" }.compactMap { $0["task_id"]?.stringValue }
        } else {
            approvals = []
            retries = []
        }
        noteWhoseRetries(new: retries.filter { !earlier.contains($0) }, stopped: lastLive.subtracting(live))
        lastLive = live
    }

    /// A retry names only its task. One that appears just as one member stops answering is that
    /// member's; with more at once, there's no telling which is whose.
    private func noteWhoseRetries(new: [String], stopped: Set<String>) {
        retryMembers = retryMembers.filter { retries.contains($0.key) }
        if new.count == 1, stopped.count == 1, let member = stopped.first { retryMembers[new[0]] = member }
    }

    /// The member whose turn `taskID` is, when it could be told.
    public func retryMember(_ taskID: String) -> String? { retryMembers[taskID] }

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
                unsent = text
                let reason = AppModel.describe(error)
                state.addNotice(
                    String(localized: "Your message didn't send, so it's back in the message box: \(reason)"))
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

    /// Runs a turn that stopped partway again.
    public func retry(_ taskID: String) {
        retries.removeAll { $0 == taskID }
        guard let channel = channel() else { return }
        Task {
            do {
                _ = try await channel.call(
                    "groups.retry", params: ["room_id": .string(roomID), "task_id": .string(taskID)])
            } catch {
                state.addNotice(String(localized: "The reply wasn't tried again: \(AppModel.describe(error))"))
            }
            await sync()
        }
    }

    /// Gives up on a turn that stopped partway. The dashboard socket has no `groups.discard`, so
    /// this is `groups.stop`, which also stops any other turn running or waiting in the room.
    public func dismiss(_ taskID: String) {
        retries.removeAll { $0 == taskID }
        guard let channel = channel() else { return }
        Task {
            do {
                _ = try await channel.call(
                    "groups.stop",
                    params: ["room_id": .string(roomID), "cancel_id": .string("usualbot-\(UUID().uuidString)")])
            } catch {
                state.addNotice(String(localized: "The reply wasn't dismissed: \(AppModel.describe(error))"))
            }
            await sync()
        }
    }

    func rename(to name: String, on channel: JSONRPCChannel) async throws {
        _ = try await channel.call(
            "groups.rename",
            params: [
                "room_id": .string(roomID), "event_id": .string(UUID().uuidString.lowercased()), "name": .string(name),
            ])
    }

    func disband(on channel: JSONRPCChannel) async throws {
        _ = try await channel.call(
            "groups.disband",
            params: ["room_id": .string(roomID), "cancel_id": .string("usualbot-\(UUID().uuidString)")])
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
        static func sample(
            _ summary: RoomSummary, events: [JSONValue], retries: [String: String?] = [:]
        ) -> RoomThread {
            let room = RoomThread(summary: summary, channel: { nil })
            room.state.apply(events.compactMap(RoomEvent.init))
            room.retries = retries.keys.sorted()
            room.retryMembers = retries.compactMapValues { $0 }
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
