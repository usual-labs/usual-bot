import Foundation
import os

/// A notification from the gateway: `{"method":"event","params":{"type",…,"payload"}}`.
public struct GatewayEvent: Sendable, Equatable {
    public let type: String
    public let sessionID: String?
    public let seq: Int?
    public let payload: JSONValue
}

/// The first frame on every socket. `session_authority: true` means the gateway runs the
/// canonical session protocol (`hermes gateway`); without it, the legacy one (`hermes dashboard`).
public struct GatewayReady: Sendable, Equatable {
    public enum Dialect: String, Sendable {
        case canonical, legacy
    }

    public let dialect: Dialect
    public let replayEpoch: JSONValue?
}

/// JSON-RPC 2.0 over one WebSocket: numbered requests with replies, a stream of events,
/// and a heartbeat (`gateway.ping` every 15 s; the socket is dead after 45 s of silence).
public actor JSONRPCChannel {
    public nonisolated let events: AsyncStream<GatewayEvent>

    private let socket: any WebSocketConnection
    private let eventSink: AsyncStream<GatewayEvent>.Continuation
    private let heartbeatInterval: Duration
    private let silenceLimit: Duration
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    private var ready: Result<GatewayReady, any Error>?
    private var readyWaiters: [CheckedContinuation<GatewayReady, any Error>] = []
    private var lastInbound = ContinuousClock.now
    private var closedError: GatewayError?
    private var tasks: [Task<Void, Never>] = []

    private static let log = Logger(subsystem: "UsualBot", category: "gateway")

    public init(
        socket: any WebSocketConnection, heartbeatInterval: Duration = .seconds(15),
        silenceLimit: Duration = .seconds(45)
    ) {
        self.socket = socket
        self.heartbeatInterval = heartbeatInterval
        self.silenceLimit = silenceLimit
        (events, eventSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Starts reading frames and sending heartbeats.
    public func start() {
        tasks.append(Task { [weak self] in await self?.readLoop() })
        tasks.append(Task { [weak self] in await self?.heartbeatLoop() })
    }

    /// Waits for `gateway.ready`.
    public func waitUntilReady(timeout: Duration = .seconds(15)) async throws -> GatewayReady {
        if let ready { return try ready.get() }
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.resolveReady(.failure(GatewayError.timedOut))
        }
        return try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }

    /// Sends a request and waits for its result. JSON-RPC errors throw `.rpc`.
    public func call(_ method: String, params: JSONValue = [:], timeout: Duration = .seconds(30)) async throws
        -> JSONValue
    {
        if let closedError { throw closedError }
        let id = nextID
        nextID += 1
        let frame: JSONValue = [
            "jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params,
        ]
        let text = String(decoding: try JSONEncoder().encode(frame), as: UTF8.self)
        #if DEBUG
            FrameRecorder.record("out", text)
        #endif
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.resolve(id: id, with: .failure(GatewayError.timedOut))
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { [weak self] in
                do {
                    try await self?.socket.send(text)
                } catch {
                    await self?.shutDown(.disconnected)
                }
            }
        }
    }

    /// Closes the socket and fails everything still waiting.
    public func close() {
        shutDown(.disconnected)
    }

    // MARK: - Inbound

    private func readLoop() async {
        while closedError == nil {
            do {
                let text = try await socket.receive()
                handle(text)
            } catch {
                shutDown(.disconnected)
            }
        }
    }

    func handle(_ text: String) {
        lastInbound = .now
        #if DEBUG
            FrameRecorder.record("in", text)
        #endif
        guard let frame = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
            Self.log.error("Dropped a frame that isn't JSON")
            return
        }
        if let id = frame["id"]?.intValue, frame["method"] == nil {
            if let error = frame["error"] {
                let rpc = GatewayError.rpc(
                    code: error["code"]?.intValue ?? 0,
                    message: error["message"]?.stringValue ?? String(localized: "The gateway refused the request."))
                resolve(id: id, with: .failure(rpc))
            } else {
                resolve(id: id, with: .success(frame["result"] ?? .null))
            }
            return
        }
        guard frame["method"]?.stringValue == "event", let params = frame["params"],
            let type = params["type"]?.stringValue
        else {
            // Server-to-client requests (approvals, questions) arrive in a later milestone.
            return
        }
        let payload = params["payload"] ?? .null
        if type == "gateway.ready" {
            let dialect: GatewayReady.Dialect = payload["session_authority"]?.boolValue == true ? .canonical : .legacy
            Self.log.info("Gateway ready, \(dialect.rawValue, privacy: .public) protocol")
            resolveReady(.success(GatewayReady(dialect: dialect, replayEpoch: payload["replay_epoch"])))
            return
        }
        eventSink.yield(
            GatewayEvent(
                type: type, sessionID: params["session_id"]?.stringValue, seq: params["seq"]?.intValue, payload: payload
            ))
    }

    private func resolve(id: Int, with result: Result<JSONValue, any Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func resolveReady(_ result: Result<GatewayReady, any Error>) {
        guard ready == nil else { return }
        ready = result
        for waiter in readyWaiters { waiter.resume(with: result) }
        readyWaiters.removeAll()
    }

    // MARK: - Heartbeat and shutdown

    private func heartbeatLoop() async {
        while closedError == nil {
            try? await Task.sleep(for: heartbeatInterval)
            guard closedError == nil else { return }
            if ContinuousClock.now - lastInbound > silenceLimit {
                Self.log.error("No frame from the gateway for \(self.silenceLimit), closing")
                shutDown(.timedOut)
                return
            }
            Task { [weak self] in _ = try? await self?.call("gateway.ping", timeout: .seconds(10)) }
        }
    }

    private func shutDown(_ error: GatewayError) {
        guard closedError == nil else { return }
        closedError = error
        socket.close()
        for continuation in pending.values { continuation.resume(throwing: error) }
        pending.removeAll()
        resolveReady(.failure(error))
        eventSink.finish()
        for task in tasks { task.cancel() }
    }
}
