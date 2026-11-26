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

/// Delay before reconnect attempt `attempt` (0-based): 300 ms doubling to a 15 s cap.
enum Backoff {
    static func delay(attempt: Int) -> Duration {
        let milliseconds = 300.0 * pow(2, Double(min(attempt, 10)))
        return .milliseconds(Int(min(milliseconds, 15_000)))
    }
}
