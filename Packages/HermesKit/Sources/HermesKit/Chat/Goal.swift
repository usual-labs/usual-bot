import Foundation

/// A goal a Bot keeps working toward by itself, reply after reply (Hermes's `/goal`). Hermes keeps
/// it with the chat: after each reply it checks whether the goal is done, and if not sends the Bot
/// on to the next step, until the goal is done, stopped, or out of turns.
public struct Goal: Equatable, Sendable, Codable {
    public enum Status: String, Sendable, Codable {
        case active
        /// Hermes's word for stopped: by you, out of turns, or because it can't go on.
        case paused
        case done
    }

    /// Why a goal isn't going on.
    public enum StopReason: Equatable, Sendable {
        case byYou
        case outOfTurns
        /// Hermes judged it can't be finished as it stands, and said why.
        case blocked(String)
        /// Anything else Hermes gave as its reason, in its own words.
        case other(String)
    }

    /// The goal in the words it was set with.
    public var text: String
    public var status: Status
    /// Replies counted against the goal so far, yours included: each one is a turn.
    public var turnsUsed: Int
    public var turnsAllowed: Int
    /// What was added to it since (`/subgoal`): all of it has to hold for the goal to be done.
    public var criteria: [String] = []
    /// Hermes's own reason for stopping it.
    var pausedReason: String?
    /// What Hermes's last check after a reply concluded.
    public var lastCheck: String?
    /// What an active goal is waiting for, when Hermes parked it: a background process, or a time.
    public var waitingOn: String?
    public var isWaiting = false

    public init(
        text: String, status: Status = .active, turnsUsed: Int = 0, turnsAllowed: Int = 20, criteria: [String] = [],
        pausedReason: String? = nil, lastCheck: String? = nil, waitingOn: String? = nil, isWaiting: Bool = false
    ) {
        self.text = text
        self.status = status
        self.turnsUsed = turnsUsed
        self.turnsAllowed = turnsAllowed
        self.criteria = criteria
        self.pausedReason = pausedReason
        self.lastCheck = lastCheck
        self.waitingOn = waitingOn
        self.isWaiting = isWaiting
    }

    /// `goal` in a control snapshot (`session.control.read`, `session.control.update`). `nil` for
    /// no goal, and for a state this app doesn't know: showing nothing beats showing it wrongly.
    init?(_ value: JSONValue?) {
        guard let value, let text = value["title"]?.stringValue?.nonBlank,
            let status = value["status"]?.stringValue.flatMap(Status.init)
        else { return nil }
        self.text = text
        self.status = status
        turnsUsed = value["turns_used"]?.intValue ?? 0
        turnsAllowed = value["max_turns"]?.intValue ?? 0
        criteria = CanonicalProtocol.rows(value["subgoals"]).compactMap { $0.stringValue?.nonBlank }
        pausedReason = value["paused_reason"]?.stringValue?.nonBlank
        lastCheck = value["last_reason"]?.stringValue?.nonBlank
        if let barrier = value["wait_barrier"], case .object = barrier {
            isWaiting = true
            waitingOn = barrier["reason"]?.stringValue?.nonBlank
        }
    }

    /// Why a stopped goal stopped. Hermes says it in a sentence of its own; its three usual ones
    /// are told apart by how they start (`hermes_cli/goals.py`).
    public var stopReason: StopReason? {
        guard status == .paused else { return nil }
        guard let reason = pausedReason, reason != "user-paused" else { return .byYou }
        if reason.hasPrefix("turn budget exhausted") { return .outOfTurns }
        let blocked = "judged unachievable: "
        if reason.hasPrefix(blocked) { return .blocked(String(reason.dropFirst(blocked.count))) }
        return .other(reason)
    }

    /// Why a stopped goal stopped, as a sentence.
    public var stopSentence: String {
        switch stopReason {
        case .byYou, nil: String(localized: "Stopped by you.")
        case .outOfTurns: String(localized: "Stopped: it used all \(turnsAllowed) of its turns.")
        case .blocked(let reason): String(localized: "Stopped: Hermes found it can't go on. \(reason)")
        case .other(let reason): String(localized: "Stopped by Hermes: \(reason)")
        }
    }
}

/// How a chat's goal stands right now: Hermes's state for it, and whether anything is running.
public enum GoalPhase: Equatable, Sendable {
    /// The Bot is replying, or Hermes is about to send it on.
    case working
    /// Parked by Hermes until something finishes.
    case waiting
    /// Still set, but nothing is running and nothing will start by itself: a reply was stopped
    /// before it said anything, failed, or the gateway restarted.
    case notRunning
    case stopped
    case done
}
