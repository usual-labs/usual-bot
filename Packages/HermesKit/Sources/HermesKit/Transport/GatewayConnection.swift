import Foundation

/// Opens an authenticated JSON-RPC socket to a gateway: mint a ticket, dial `/api/ws?ticket=…`,
/// wait for `gateway.ready`.
struct GatewayConnector: Sendable {
    typealias SocketFactory = @Sendable (URL) async throws -> any WebSocketConnection

    private let auth: AuthSession
    private let makeSocket: SocketFactory

    init(auth: AuthSession, makeSocket: @escaping SocketFactory = { URLSessionWebSocket(url: $0) }) {
        self.auth = auth
        self.makeSocket = makeSocket
    }

    func connect(attempt: Int = 0) async throws -> (JSONRPCChannel, GatewayReady) {
        let total = Trace.begin("connect", "attempt=\(attempt)")
        var step = Trace.begin("connect.ticket")
        do {
            let ticket = try await auth.webSocketTicket()
            step.end()
            step = Trace.begin("connect.socket")
            let channel = JSONRPCChannel(socket: try await makeSocket(auth.gateway.webSocketURL(ticket: ticket)))
            await channel.start()
            step.end()
            do {
                step = Trace.begin("connect.ready")
                let ready = try await channel.waitUntilReady()
                step.end("dialect=\(ready.dialect.rawValue)")
                step = Trace.begin("connect.capabilities")
                // Without this the gateway fails approval requests at once instead of asking the app.
                _ = try await channel.call("client.capabilities", params: ["server_requests": true])
                step.end()
                total.end("ok")
                return (channel, ready)
            } catch {
                await channel.close()
                throw error
            }
        } catch {
            step.end("error=\(Trace.reason(error))")
            total.end("error=\(Trace.reason(error))")
            throw error
        }
    }
}

/// Delay before reconnect attempt `attempt` (0-based): 300 ms doubling to a 15 s cap, then cut to
/// a random share of that (`jitter`, half to all of it), so phones that lost the same network
/// don't all come back at once, and one retry that keeps landing in a bad moment moves.
enum Backoff {
    static func delay(attempt: Int, jitter: Double = .random(in: 0.5...1)) -> Duration {
        let milliseconds = 300.0 * pow(2, Double(min(attempt, 10)))
        return .milliseconds(Int(min(milliseconds, 15_000) * jitter))
    }
}
