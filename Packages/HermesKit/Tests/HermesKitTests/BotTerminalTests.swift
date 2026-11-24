import Foundation
import Synchronization
import Testing

@testable import HermesKit

@MainActor
struct BotTerminalTests {
    private final class Sockets: Sendable {
        let opened = Mutex<[(URL, ScriptedScreenSocket)]>([])
        var all: [(URL, ScriptedScreenSocket)] { opened.withLock { $0 } }
    }

    /// A shell whose gateway answers the status route with `status` and mints tickets t1, t2, ….
    private func make(
        status: (Int, String) = (
            200, #"{"available":true,"backend":"local","user":"me","host":"box","cwd":"/home/me/work"}"#
        )
    ) -> (BotTerminal, ScriptedHTTP, Sockets) {
        let tickets = Mutex(0)
        let http = ScriptedHTTP { request in
            if request.url?.path() == "/api/auth/ws-ticket" {
                let next = tickets.withLock { count in
                    count += 1
                    return count
                }
                return (200, #"{"ticket":"t\#(next)"}"#)
            }
            return status
        }
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        let sockets = Sockets()
        let terminal = BotTerminal(
            profile: "scout", auth: { auth },
            makeSocket: { url in
                let socket = ScriptedScreenSocket()
                sockets.opened.withLock { $0.append((url, socket)) }
                return socket
            })
        return (terminal, http, sockets)
    }

    private func socket(_ sockets: Sockets, _ index: Int = 0) async throws -> ScriptedScreenSocket {
        try await waitUntilOnMain { sockets.all.count > index }
        return sockets.all[index].1
    }

    private static func output(_ text: String) -> [UInt8] { [0] + Array(text.utf8) }
    private static func control(_ json: String) -> [UInt8] { [1] + Array(json.utf8) }

    @Test func statusSaysWhetherTheBotHasAShell() async {
        let (terminal, http, _) = make()
        await terminal.refresh()
        #expect(terminal.availability == .available)
        #expect(terminal.place == BotTerminal.Place(user: "me", host: "box", folder: "/home/me/work"))
        #expect(
            http.requests.last?.url?.absoluteString
                == "http://100.101.102.103:9119/api/plugins/usual-bot/terminal/status?bot=scout")

        let (sandboxed, _, _) = make(status: (200, #"{"available":false,"backend":"docker"}"#))
        await sandboxed.refresh()
        #expect(sandboxed.availability == .sandboxed(backend: "docker"))

        let (old, _, _) = make(status: (404, #"{"detail":"Not Found"}"#))
        await old.refresh()
        #expect(old.availability == .noPlugin)
    }

    @Test func theShellPrintsAndTakesTyping() async throws {
        let (terminal, _, sockets) = make()
        terminal.resize(columns: 100, rows: 30)
        terminal.start()
        let socket = try await socket(sockets)
        #expect(
            sockets.all[0].0.absoluteString
                == "ws://100.101.102.103:9119/api/plugins/usual-bot/terminal?bot=scout&ticket=t1&cols=100&rows=30")
        socket.deliver(Self.control(#"{"type":"ready","user":"me","host":"box","cwd":"/w"}"#), frame: 1000)
        socket.deliver(Self.output("$ "), frame: 1000)
        try await waitUntilOnMain { terminal.screen.text == "$" }
        #expect(terminal.connection == .live)
        #expect(terminal.place?.folder == "/w")

        terminal.send("ls\r")
        try await waitUntilOnMain { socket.sent.count == 2 }
        // The size goes first, as soon as the shell is ready.
        #expect(socket.sent[0].first == 1)
        let size = try JSONDecoder().decode(JSONValue.self, from: Data(socket.sent[0].dropFirst()))
        #expect(size["cols"]?.intValue == 100)
        #expect(socket.sent[1] == Self.output("ls\r"))

        terminal.resize(columns: 90, rows: 30)
        try await waitUntilOnMain { socket.sent.count == 3 }
        #expect(terminal.screen.columns == 90)

        socket.deliver(Self.control(#"{"type":"exit","code":0}"#), frame: 1000)
        try await waitUntilOnMain { terminal.connection == .ended(code: 0) }
    }

    @Test func pasteIsMarkedWhenTheShellAsks() async throws {
        let (terminal, _, sockets) = make()
        terminal.start()
        let socket = try await socket(sockets)
        socket.deliver(Self.output("\u{1B}[?2004h$ "), frame: 1000)
        try await waitUntilOnMain { terminal.screen.bracketedPaste }
        terminal.paste("a\nb")
        try await waitUntilOnMain { !socket.sent.isEmpty }
        #expect(socket.sent.last == Self.output("\u{1B}[200~a\rb\u{1B}[201~"))
    }

    @Test func theScreenAnswersTheShell() async throws {
        let (terminal, _, sockets) = make()
        terminal.start()
        let socket = try await socket(sockets)
        socket.deliver(Self.output("ab\u{1B}[6n"), frame: 1000)
        try await waitUntilOnMain { !socket.sent.isEmpty }
        #expect(socket.sent[0] == Self.output("\u{1B}[1;3R"))
    }

    @Test func aStaleTicketTriesOnceMore() async throws {
        let (terminal, _, sockets) = make()
        terminal.start()
        try await socket(sockets).serverClose(4401)
        let second = try await socket(sockets, 1)
        #expect(sockets.all[1].0.absoluteString.contains("ticket=t2"))
        second.serverClose(4409)
        try await waitUntilOnMain {
            if case .failed = terminal.connection { true } else { false }
        }
    }

    @Test func aLostConnectionSaysWhatStopped() async throws {
        let (terminal, _, sockets) = make()
        terminal.start()
        try await socket(sockets).serverClose(1006)
        try await waitUntilOnMain { terminal.connection != .connecting }
        #expect(terminal.connection == .failed("Lost the connection to the shell. What ran in it was stopped."))
        // Starting again opens a new shell.
        terminal.start()
        _ = try await socket(sockets, 1)
        terminal.stop()
        #expect(terminal.connection == .idle)
    }
}

struct BotCommandTests {
    @Test func aCommandKeepsWhatItPrinted() {
        var state = ThreadState()
        state.apply(GatewayEvent(type: "message.start", sessionID: "s", seq: nil, payload: [:]))
        state.apply(
            GatewayEvent(
                type: "tool.start", sessionID: "s", seq: nil,
                payload: [
                    "tool_id": "t1", "name": "terminal", "context": "npm te…",
                    "args": ["command": "npm test -- search"],
                ]))
        #expect(state.isRunningCommand)
        state.apply(
            GatewayEvent(
                type: "tool.complete", sessionID: "s", seq: nil,
                payload: ["tool_id": "t1", "result": ["output": "1 failing", "exit_code": 1]]))
        #expect(!state.isRunningCommand)
        let step = try! #require(state.commands.first?.step)
        #expect(step.commandLine == "npm test -- search")
        #expect(step.output == "1 failing")
        #expect(step.exitCode == 1)
        #expect(step.state == .failed)
    }

    @Test func otherToolsAreNotCommands() {
        var state = ThreadState()
        state.apply(GatewayEvent(type: "message.start", sessionID: "s", seq: nil, payload: [:]))
        state.apply(
            GatewayEvent(
                type: "tool.start", sessionID: "s", seq: nil,
                payload: ["tool_id": "t1", "name": "read_file", "context": "notes.md"]))
        #expect(state.commands.isEmpty)
        #expect(!state.isRunningCommand)
    }

    @Test func longOutputKeepsItsEnd() {
        let lines = (1...3000).map { "line \($0)" }.joined(separator: "\n")
        let kept = BotCommand.kept(lines)
        #expect(kept.count <= BotCommand.outputLimit)
        #expect(kept.hasSuffix("line 3000"))
        #expect(kept.hasPrefix("line "))
    }
}
