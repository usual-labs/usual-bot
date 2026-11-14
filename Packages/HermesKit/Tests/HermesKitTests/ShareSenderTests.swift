import Foundation
import Testing

@testable import HermesKit

/// The share extension sending for you, against a scripted gateway.
struct ShareSenderTests {
    private let hermes = Contact(id: "hermes", name: "Hermes", chatID: "local-1")
    private let idle: JSONValue = [
        "session_id": "local-1", "running": false, "execution_generation": 3, "revision": 5,
        "subscription_id": "sub-1", "replay_epoch": "e1", "last_sequence": 0, "display_messages": [],
    ]

    private struct Setup {
        let folder = ShareFolder()
        let gateway = ScriptedGateway()
        let store = MemoryTokenStore()

        init() throws {
            try store.save(
                TokenSet(
                    accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                    userID: "u1"),
                for: testGateway)
        }

        func sender(http: ScriptedHTTP? = nil, timeout: Duration = .seconds(15)) -> ShareSender {
            let socket = gateway.socket
            return ShareSender(
                container: folder.container, store: store,
                http: http ?? ScriptedHTTP { _ in (200, #"{"ticket":"t1","ttl_seconds":30}"#) },
                makeSocket: { _ in socket }, openTimeout: timeout)
        }

        func roster(builtInTailscale: Bool = false, _ contacts: [Contact]) -> ShareRoster {
            ShareRoster(
                gateway: testGateway.fileName, contacts: contacts, address: testGateway,
                usesBuiltInTailscale: builtInTailscale)
        }

        func share(_ text: String, files: [SharedContent.File] = [], to contact: Contact) throws -> SharedItem {
            var content = SharedContent()
            content.addText(text)
            for file in files { content.add(file) }
            return try folder.container.add(content, note: "", to: contact, gateway: testGateway.fileName)
        }

        /// The gateway's own listener says hello, and the app's capabilities are request 0.
        func ready(canonical: Bool = true) async throws {
            gateway.socket.deliver(
                #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"session_authority":\#(canonical)}}}"#
            )
            _ = try await gateway.answer(0, method: "client.capabilities")
        }
    }

    @Test func aMessageGoesStraightToTheChatUnderItsOwnID() async throws {
        let setup = try Setup()
        defer { setup.folder.remove() }
        let item = try setup.share("https://example.com/post", to: hermes)

        async let outcome = setup.sender().send(item, to: hermes, roster: setup.roster([hermes]))
        try await setup.ready()
        let resume = try await setup.gateway.answer(1, method: "session.resume", result: idle)
        #expect(resume["session_id"] == "local-1")
        let submit = try await setup.gateway.answer(2, method: "prompt.submit", result: ["status": "queued"])

        #expect(await outcome == .sent)
        #expect(submit["text"] == "https://example.com/post")
        // The app sends a waiting item under the same ID, so the gateway would take it once.
        #expect(submit["submission_id"] == .string(item.id.uuidString))
        #expect(setup.folder.container.items().isEmpty)
    }

    @Test func aFileIsUploadedAndReferencedInTheMessage() async throws {
        let setup = try Setup()
        defer { setup.folder.remove() }
        let pdf = try setup.folder.file("report.pdf", Data("%PDF".utf8))
        let item = try setup.share("Summarise this", files: [pdf], to: hermes)

        async let outcome = setup.sender().send(item, to: hermes, roster: setup.roster([hermes]))
        try await setup.ready()
        _ = try await setup.gateway.answer(1, method: "session.resume", result: idle)
        _ = try await setup.gateway.answer(
            2, method: "file.attach",
            result: ["attached": true, "ref_text": "@file:attachments/report.pdf", "name": "report.pdf"])
        let submit = try await setup.gateway.answer(3, method: "prompt.submit", result: ["status": "queued"])

        #expect(await outcome == .sent)
        #expect(submit["text"] == "Summarise this\n\n@file:attachments/report.pdf")
        #expect(setup.folder.container.items().isEmpty)
    }

    @Test func aFileThatMayHaveGoneIsShownNotSentAgain() async throws {
        let setup = try Setup()
        defer { setup.folder.remove() }
        let pdf = try setup.folder.file("report.pdf", Data("%PDF".utf8))
        let item = try setup.share("", files: [pdf], to: hermes)

        async let outcome = setup.sender().send(item, to: hermes, roster: setup.roster([hermes]))
        try await setup.ready()
        _ = try await setup.gateway.answer(1, method: "session.resume", result: idle)
        _ = try await setup.gateway.answer(
            2, method: "file.attach",
            result: ["attached": true, "ref_text": "@file:attachments/report.pdf", "name": "report.pdf"])
        // The message went, but the answer never came back.
        try await waitUntil { setup.gateway.socket.sent.count > 3 }
        setup.gateway.socket.close()

        #expect(await outcome == .unconfirmed)
        let kept = try #require(setup.folder.container.items().first)
        #expect(kept.id == item.id)
        #expect(kept.failure == "This may be in the chat already. Check Hermes's chat before you try again.")
    }

    @Test func textThatMayHaveGoneWaitsForTheAppUnderTheSameID() async throws {
        let setup = try Setup()
        defer { setup.folder.remove() }
        let item = try setup.share("Hello", to: hermes)

        async let outcome = setup.sender().send(item, to: hermes, roster: setup.roster([hermes]))
        try await setup.ready()
        _ = try await setup.gateway.answer(1, method: "session.resume", result: idle)
        try await waitUntil { setup.gateway.socket.sent.count > 2 }
        setup.gateway.socket.close()

        guard case .waiting = await outcome else {
            Issue.record("expected it to wait")
            return
        }
        #expect(setup.folder.container.items() == [item])
    }

    @Test func aBusyBotLeavesItForTheApp() async throws {
        let setup = try Setup()
        defer { setup.folder.remove() }
        let item = try setup.share("Hello", to: hermes)
        var running = idle
        if case .object(var fields) = running {
            fields["running"] = true
            running = .object(fields)
        }

        async let outcome = setup.sender().send(item, to: hermes, roster: setup.roster([hermes]))
        try await setup.ready()
        _ = try await setup.gateway.answer(1, method: "session.resume", result: running)

        #expect(
            await outcome
                == .waiting(
                    "Hermes is busy right now. Usual Bot sends it once Hermes is free, the next time it's open."))
        #expect(setup.folder.container.items() == [item])
        #expect(setup.gateway.socket.sent.count == 2)
    }

    @Test func builtInTailscaleOnATailnetAddressLeavesItForTheApp() async throws {
        let setup = try Setup()
        defer { setup.folder.remove() }
        let item = try setup.share("Hello", to: hermes)
        let http = ScriptedHTTP { _ in
            Issue.record("no request expected"); return (500, "")
        }

        let outcome = await setup.sender(http: http).send(
            item, to: hermes, roster: setup.roster(builtInTailscale: true, [hermes]))

        guard case .waiting(let reason?) = outcome else {
            Issue.record("expected a reason")
            return
        }
        #expect(reason.contains("built-in Tailscale"))
        #expect(setup.folder.container.items() == [item])
    }

    @Test func theDashboardRoomsAndAnUnreachableGatewayLeaveItForTheApp() async throws {
        let setup = try Setup()
        defer { setup.folder.remove() }
        let item = try setup.share("Hello", to: hermes)

        // The dashboard's socket can't tell a retry from a second message.
        async let dashboard = setup.sender().send(item, to: hermes, roster: setup.roster([hermes]))
        try await setup.ready(canonical: false)
        #expect(await dashboard == .waiting(nil))
        #expect(setup.gateway.socket.sent.count == 1)

        let room = Contact(id: "room:r1", name: "Launch room", kind: .room(memberIDs: ["hermes"]))
        #expect(await setup.sender().send(item, to: room, roster: setup.roster([hermes, room])) == .waiting(nil))

        let offline = ScriptedHTTP { _ in throw GatewayError.unreachable("offline") }
        guard
            case .waiting(let reason?) = await setup.sender(http: offline).send(
                item, to: hermes, roster: setup.roster([hermes]))
        else {
            Issue.record("expected a reason")
            return
        }
        #expect(reason.hasPrefix("Couldn't reach your gateway"))
        #expect(setup.folder.container.items() == [item])
    }

    @Test func aGatewayThatDoesNotAnswerIsLeftForTheApp() async throws {
        let setup = try Setup()
        defer { setup.folder.remove() }
        let item = try setup.share("Hello", to: hermes)

        // Ready never comes.
        let outcome = await setup.sender(timeout: .milliseconds(200)).send(
            item, to: hermes, roster: setup.roster([hermes]))

        guard case .waiting(let reason?) = outcome else {
            Issue.record("expected a reason")
            return
        }
        #expect(reason.hasPrefix("Couldn't reach your gateway"))
        #expect(setup.folder.container.items() == [item])
    }
}
