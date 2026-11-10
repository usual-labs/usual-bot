import Foundation

/// A room's lead, routing, purpose and notes, and carrying on a discussion paused at its cap.
extension RoomThread {
    /// `groups.state`'s `context`, and the routing the room service takes. A gateway before
    /// Hermes 0.23 sends no context; one with a purpose and notes but no routing sends no `routing`.
    func readSettings(_ result: JSONValue) {
        guard let context = result["context"], context != .null else {
            settings = nil
            routingModes = []
            maxContinues = nil
            return
        }
        let read = RoomSettings(context)
        settings = read
        let status = result["driver_status"]
        maxContinues = status?["max_continues"]?.intValue
        guard context["routing"] != nil else {
            routingModes = []
            return
        }
        // A room service that doesn't list them is one from before `auto`.
        var modes: [RoomRouting] = [.everyone, .lead]
        if case .array(let listed) = status?["routing_modes"] {
            modes = RoomRouting.allCases.filter { listed.contains(.string($0.rawValue)) }
        }
        // The room's own stays offered, as the official app keeps it.
        if !modes.contains(read.routing) { modes.append(read.routing) }
        routingModes = modes
    }

    /// The lead's member ID, while the lead picks who answers.
    public var leadID: String? { settings?.routing == .lead ? settings?.leadID : nil }

    /// Saves the room's settings for everyone in it. Members see them from the next message.
    func save(_ changed: RoomSettings, on channel: JSONRPCChannel) async throws {
        let result = try await channel.call(
            "groups.context", params: changed.params(roomID: roomID, routes: !routingModes.isEmpty))
        settings = result["context"].map(RoomSettings.init) ?? changed
    }

    /// The same with no gateway, for the demo.
    func adopt(_ changed: RoomSettings) {
        settings = changed
    }

    /// Sets a new room's routing: `groups.create` takes none, so it follows as its own call.
    static func setRouting(_ settings: RoomSettings, roomID: String, on channel: JSONRPCChannel) async throws {
        _ = try await channel.call("groups.context", params: settings.params(roomID: roomID, routes: true))
    }

    /// The discussion paused at its cap, while it can still carry on.
    public var pause: PausedDiscussion? {
        guard let pause = state.pause, let maxContinues, pause.grant <= maxContinues,
            !answeredPauses.contains(pause.id)
        else { return nil }
        return pause
    }

    /// How many more times `pause` can carry on, this one included.
    public func continuesLeft(_ pause: PausedDiscussion) -> Int {
        max((maxContinues ?? 0) - pause.grant + 1, 0)
    }

    /// Lets the Bots carry on a discussion the gateway paused at its cap, for one more budget.
    public func carryOn(_ pause: PausedDiscussion) {
        guard let channel = channel() else { return }
        answeredPauses.insert(pause.id)
        Task {
            do {
                _ = try await channel.call(
                    "groups.continue",
                    params: ["room_id": .string(roomID), "discussion_event_id": .string(pause.discussionID)])
            } catch {
                answeredPauses.remove(pause.id)
                addNotice(String(localized: "The discussion didn't carry on: \(AppModel.describe(error))"))
            }
            await sync()
        }
    }

    /// Leaves a paused discussion where it stopped. Nothing is told to the gateway: the offer
    /// only goes from this device, until the app next starts.
    public func leavePaused(_ pause: PausedDiscussion) {
        answeredPauses.insert(pause.id)
    }
}
