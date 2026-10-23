import Foundation

/// Opens an authenticated JSON-RPC socket to a gateway: mint a ticket, dial `/api/ws?ticket=…`,
/// wait for `gateway.ready`.
struct GatewayConnector: Sendable {
    typealias SocketFactory = @Sendable (URL) -> any WebSocketConnection

    private let auth: AuthSession
    private let makeSocket: SocketFactory

    init(auth: AuthSession, makeSocket: @escaping SocketFactory = { URLSessionWebSocket(url: $0) }) {
        self.auth = auth
        self.makeSocket = makeSocket
    }

    func connect() async throws -> (JSONRPCChannel, GatewayReady) {
        let ticket = try await auth.webSocketTicket()
        let channel = JSONRPCChannel(socket: makeSocket(auth.gateway.webSocketURL(ticket: ticket)))
        await channel.start()
        do {
            let ready = try await channel.waitUntilReady()
            // Without this the gateway fails approval requests at once instead of asking the app.
            _ = try await channel.call("client.capabilities", params: ["server_requests": true])
            return (channel, ready)
        } catch {
            await channel.close()
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
