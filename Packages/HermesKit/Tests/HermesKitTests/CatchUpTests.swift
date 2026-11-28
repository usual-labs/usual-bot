import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// A chat back from a dropped link, on the gateway's own listener: it takes in what it missed
/// instead of the whole transcript, keeps what it shows when the gateway is slow, and loads in
/// full when the gateway no longer has what it missed.
@MainActor
struct CatchUpTests {
    /// The socket the chat uses now, swapped as the link drops and comes back.
    private final class Link {
        var channel: JSONRPCChannel?
    }

    private func connect(_ recording: RecordedGatewayTests.Recording) async throws -> (JSONRPCChannel, ScriptedGateway)
    {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        try gateway.socket.deliver(try #require(recording.ready))
        _ = try await channel.waitUntilReady()
        return (channel, gateway)
    }

    private func route(_ channel: JSONRPCChannel, to thread: ChatThread) -> Task<Void, Never> {
        let events = channel.events
        return Task { @MainActor in for await event in events { thread.apply(event) } }
    }

    /// The chat turn's numbered frames, each as the event `params` a replay or the socket carries.
    private func frames(_ recording: RecordedGatewayTests.Recording) throws -> [JSONValue] {
        try recording.events(after: "prompt.submit").compactMap(\.["params"]).filter { $0["seq"] != nil }
    }

    /// Attaches `thread` on a first socket, sends the recorded message, takes the reply's frames up
    /// to `cut`, then drops the link. Returns the question and the frames not taken.
    private func startTurnThenDrop(
        _ thread: ChatThread, link: Link, recording: RecordedGatewayTests.Recording, cut: Int
    ) async throws -> (question: String, rest: [JSONValue]) {
        let (channel, gateway) = try await connect(recording)
        link.channel = channel
        let routing = route(channel, to: thread)
        defer { routing.cancel() }
        thread.open(knownID: "local-chat", dialect: .canonical)
        _ = try await gateway.answer(0, method: "session.resume", result: recording.result(of: "session.resume"))
        try await waitUntilOnMain { thread.isAttached }
        let question = try #require(recording.params(of: "prompt.submit")["text"]?.stringValue)
        thread.send(question)
        _ = try await gateway.answer(1, method: "prompt.submit", result: recording.result(of: "prompt.submit"))
        let all = try frames(recording)
        for frame in all.prefix(cut) {
            try gateway.socket.deliver(["jsonrpc": "2.0", "method": "event", "params": frame])
        }
        let seen = try #require(all[cut - 1]["seq"]?.intValue)
        try await waitUntilOnMain { thread.lastSeq == seen }
        thread.detach()
        await channel.close()
        return (question, Array(all.dropFirst(cut)))
    }

    /// The recorded attach as the gateway answers one without the transcript, at `last`.
    private func resumedWithoutMessages(_ recording: RecordedGatewayTests.Recording, last: Int) throws -> JSONValue {
        guard case .object(var result) = try recording.result(of: "session.resume") else { return .null }
        result["messages"] = []
        result["display_messages"] = []
        result["messages_omitted"] = true
        result["last_sequence"] = .number(Double(last))
        return .object(result)
    }

    @Test func aChatBackFromAShortDropTakesInOnlyWhatItMissed() async throws {
        let recording = try RecordedGatewayTests.Recording("canonical-chat-turn")
        let link = Link()
        let thread = ChatThread(contactID: "scout", channel: { link.channel })
        let (question, rest) = try await startTurnThenDrop(thread, link: link, recording: recording, cut: 3)
        #expect(thread.state.isRunning)
        let loads = thread.transcriptLoad
        let seen = thread.lastSeq
        let epoch = try #require(rest.first?["replay_epoch"])

        let (channel, gateway) = try await connect(recording)
        link.channel = channel
        let routing = route(channel, to: thread)
        defer { routing.cancel() }
        thread.open(knownID: "local-chat", dialect: .canonical)
        let asked = try await gateway.answer(
            0, method: "session.events.since",
            result: [
                "events": .array(rest), "truncated": false, "snapshot_required": false, "replay_epoch": epoch,
            ])
        #expect(asked["last_sequence"]?.intValue == seen)
        #expect(asked["replay_epoch"] == epoch)
        #expect(asked["profile"] == "scout")
        let last = try #require(rest.last?["seq"]?.intValue)
        let resumed = try await gateway.answer(
            1, method: "session.resume", result: resumedWithoutMessages(recording, last: last))
        #expect(resumed["omit_messages"] == true)
        try await waitUntilOnMain { thread.isAttached }

        #expect(thread.state.items.map(\.content) == [.user(question), .assistant("ECHO: \(question)")])
        #expect(!thread.state.isRunning)
        // The transcript on screen stayed: nothing reloaded under you.
        #expect(thread.transcriptLoad == loads)
        #expect(gateway.socket.sent.filter { $0["method"] == "session.resume" }.count == 1)
    }

    @Test func aChatTheGatewayLostTrackOfLoadsInFull() async throws {
        let recording = try RecordedGatewayTests.Recording("canonical-chat-turn")
        let link = Link()
        let thread = ChatThread(contactID: "scout", channel: { link.channel })
        _ = try await startTurnThenDrop(thread, link: link, recording: recording, cut: 3)

        let (channel, gateway) = try await connect(recording)
        link.channel = channel
        thread.open(knownID: "local-chat", dialect: .canonical)
        _ = try await gateway.answer(
            0, method: "session.events.since", result: ["events": [], "truncated": true, "snapshot_required": true])
        let resumed = try await gateway.answer(
            1, method: "session.resume", result: recording.result(of: "session.resume"))
        #expect(resumed["omit_messages"] == nil)
        try await waitUntilOnMain { thread.isAttached }
    }

    @Test func aChatThatLosesTheLinkWhileOpeningKeepsWhatItShows() async throws {
        let recording = try RecordedGatewayTests.Recording("canonical-chat-turn")
        let link = Link()
        let thread = ChatThread(contactID: "scout", channel: { link.channel })
        let (question, _) = try await startTurnThenDrop(thread, link: link, recording: recording, cut: 3)

        let (channel, gateway) = try await connect(recording)
        link.channel = channel
        thread.open(knownID: "local-chat", dialect: .canonical)
        try await waitUntil { gateway.socket.sent.count == 1 }
        gateway.socket.close()
        try await waitUntilOnMain { !thread.isOpening }

        #expect(thread.phase == .ready)
        #expect(thread.state.items.first?.content == .user(question))
    }

    @Test func aChatStillLoadingKeepsLoadingWhenTheLinkGoes() async throws {
        let recording = try RecordedGatewayTests.Recording("canonical-chat-turn")
        let (channel, gateway) = try await connect(recording)
        let thread = ChatThread(contactID: "scout", channel: { channel })
        thread.open(knownID: "local-chat", dialect: .canonical)
        try await waitUntil { gateway.socket.sent.count == 1 }
        gateway.socket.close()
        try await waitUntilOnMain { !thread.isOpening }

        #expect(thread.phase == .loading)
        #expect(thread.loadingSince != nil)
    }
}
