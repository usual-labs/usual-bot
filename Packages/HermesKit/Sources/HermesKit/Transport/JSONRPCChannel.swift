import Foundation
import os

/// A notification from the gateway: `{"method":"event","params":{"type",…,"payload"}}`.
public struct GatewayEvent: Sendable, Equatable {
    public let type: String
    public let sessionID: String?
    public let seq: Int?
    public let payload: JSONValue
}

/// A question the gateway asks the app and waits on, e.g. `approval`. Answer it with
/// `JSONRPCChannel.respond(to:result:)` or refuse it with `JSONRPCChannel.decline(_:code:message:)`.
/// On the canonical protocol approvals and questions come as events; the channel hands them on
/// as requests, under their `prompt_id`.
public struct ServerRequest: Sendable, Equatable {
    /// `srq-…`: strings, so they never collide with the app's own numeric request IDs.
    public let id: String
    public let method: String
    public let params: JSONValue

    public var sessionID: String? { params["session_id"]?.stringValue }
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

/// JSON-RPC 2.0 over one WebSocket: numbered requests with replies, a stream of events, the
/// gateway's own requests to the app, and a heartbeat (`gateway.ping` every 15 s; the socket is
/// dead after 45 s of silence).
///
/// The app speaks the legacy protocol throughout. On a canonical gateway the channel translates
/// each call, event and answer (`JSONRPCChannel+Canonical.swift`).
public actor JSONRPCChannel {
    public nonisolated let events: AsyncStream<GatewayEvent>
    public nonisolated let requests: AsyncStream<ServerRequest>

    private let socket: any WebSocketConnection
    private let eventSink: AsyncStream<GatewayEvent>.Continuation
    private let requestSink: AsyncStream<ServerRequest>.Continuation
    /// Frames to send, in the order they were written. One writer sends them: a task per frame
    /// could put a reply ahead of the one before it.
    private let outgoing: AsyncStream<String>
    private let outbox: AsyncStream<String>.Continuation
    private var writer: Task<Void, Never>?
    private let heartbeatInterval: Duration
    private let silenceLimit: Duration
    private var nextID = 1
    /// Which protocol the gateway speaks, from `gateway.ready`.
    public private(set) var dialect: GatewayReady.Dialect = .legacy
    var canonical = CanonicalProtocol()
    /// Canonical calls still waiting, with the session they're about: their replies carry fences
    /// that frames right behind them may need.
    private var callContexts: [Int: (method: String, sessionID: String?, profile: String?)] = [:]
    /// Calls that carried a secret. Kept after they finish: a late reply may still quote it.
    private var sensitiveCalls: Set<Int> = []
    private var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    private var ready: Result<GatewayReady, any Error>?
    private var readyWaiters: [CheckedContinuation<GatewayReady, any Error>] = []
    private var lastInbound = ContinuousClock.now
    private var closedError: GatewayError?
    /// Not closed yet, by either side or the heartbeat.
    public var isOpen: Bool { closedError == nil }
    private var tasks: [Task<Void, Never>] = []
    /// Each call still waiting, timed for `Trace`.
    private var timings: [Int: (method: String, span: Span)] = [:]
    private let openedAt = ContinuousClock.now

    private static let log = Logger(subsystem: "UsualBot", category: "gateway")

    public init(
        socket: any WebSocketConnection, heartbeatInterval: Duration = .seconds(15),
        silenceLimit: Duration = .seconds(45)
    ) {
        self.socket = socket
        self.heartbeatInterval = heartbeatInterval
        self.silenceLimit = silenceLimit
        (events, eventSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (requests, requestSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (outgoing, outbox) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
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

    /// Sends a request and waits for its result. JSON-RPC errors throw `.rpc`. A `sensitive` call
    /// carries a secret, so its reply, which may quote it, isn't recorded.
    public func call(
        _ method: String, params: JSONValue = [:], timeout: Duration = .seconds(30), sensitive: Bool = false
    ) async throws -> JSONValue {
        if dialect == .canonical {
            return try await canonicalCall(method, params: params, timeout: timeout, sensitive: sensitive)
        }
        return try await send(method, params: params, timeout: timeout, sensitive: sensitive)
    }

    /// Sends `method` as it is, with no translation.
    func send(
        _ method: String, params: JSONValue = [:], timeout: Duration = .seconds(30), sensitive: Bool = false
    ) async throws -> JSONValue {
        if let closedError { throw closedError }
        let id = nextID
        nextID += 1
        if sensitive { sensitiveCalls.insert(id) }
        if dialect == .canonical {
            callContexts[id] = (method, params["session_id"]?.stringValue, params["profile"]?.stringValue)
        }
        let frame: JSONValue = [
            "jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params,
        ]
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.resolve(id: id, with: .failure(GatewayError.timedOut))
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            let bytes = write(frame)
            timings[id] = (method, Trace.begin("rpc", "method=\(method) bytes=\(bytes) waiting=\(pending.count - 1)"))
        }
    }

    /// Answers the server request with ID `requestID`.
    public func respond(to requestID: String, result: JSONValue) {
        if dialect == .canonical, let answer = canonical.answer(requestID, result: result) {
            let params = canonical.routed(answer.method, answer.params)
            Task { [weak self] in
                do {
                    _ = try await self?.send(answer.method, params: params)
                } catch {
                    Self.log.error(
                        "The answer to a prompt didn't arrive: \(String(describing: error), privacy: .public)")
                }
            }
            return
        }
        write(["jsonrpc": "2.0", "id": .string(requestID), "result": result])
    }

    /// Refuses a server request, so the agent doesn't wait out its deadline for an answer. Not on
    /// the canonical protocol: any answer settles a request there, for every app, so one this app
    /// doesn't show is left for the others.
    public func decline(_ requestID: String, code: Int, message: String) {
        guard dialect == .legacy else { return }
        write([
            "jsonrpc": "2.0", "id": .string(requestID),
            "error": ["code": .number(Double(code)), "message": .string(message)],
        ])
    }

    /// Returns the frame's size, 0 when it wasn't sent.
    @discardableResult
    private func write(_ frame: JSONValue) -> Int {
        guard closedError == nil, let data = try? JSONEncoder().encode(frame) else { return 0 }
        let text = String(decoding: data, as: UTF8.self)
        #if DEBUG
            FrameRecorder.record("out", text)
        #endif
        outbox.yield(text)
        if writer == nil {
            writer = Task { [weak self, outgoing] in
                for await text in outgoing {
                    guard let self else { return }
                    do {
                        // Large frames are uploads: how long the socket takes, apart from the gateway.
                        let large =
                            text.utf8.count >= Self.largeFrame
                            ? Trace.begin("socket.send", "bytes=\(text.utf8.count)") : nil
                        try await socket.send(text)
                        large?.end()
                    } catch {
                        await shutDown(.disconnected)
                        return
                    }
                }
            }
        }
        return data.count
    }

    /// Frames from this size up get a line of their own, in and out.
    static let largeFrame = 256 * 1024
    /// Calls that take this long or more get a line; quicker ones only an interval.
    static let slowCall: Duration = .milliseconds(500)

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
        let quiet = ContinuousClock.now - lastInbound
        lastInbound = .now
        let large = text.utf8.count >= Self.largeFrame ? Trace.begin("frame.decode", "bytes=\(text.utf8.count)") : nil
        let decoded = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        large?.end()
        // A long silence that ended: the link may have been stalled rather than idle.
        if quiet >= .seconds(20) { Trace.event("socket.quiet", "ms=\(Trace.milliseconds(quiet))") }
        #if DEBUG
            if decoded?["id"]?.intValue.map(sensitiveCalls.contains) != true { FrameRecorder.record("in", text) }
        #endif
        guard let frame = decoded else {
            Self.log.error("Dropped a frame that isn't JSON")
            return
        }
        if let id = frame["id"]?.intValue, frame["method"] == nil {
            let context = callContexts.removeValue(forKey: id)
            if let error = frame["error"] {
                let code = error["code"]?.intValue ?? 0
                let message = error["message"]?.stringValue ?? String(localized: "The gateway refused the request.")
                if let context, let reason = error["data"]?["reason"]?.stringValue {
                    // A refusal over a stale fence carries the fresh ones.
                    if let session = context.sessionID, let data = error["data"] {
                        canonical.absorbFences(data, session: session)
                    }
                    let refusal = CanonicalRefusal(
                        code: code, reason: reason, message: message, detail: error["data"]?["detail"]?.stringValue)
                    resolve(id: id, with: .failure(refusal))
                } else {
                    resolve(id: id, with: .failure(GatewayError.rpc(code: code, message: message)))
                }
            } else {
                let result = frame["result"] ?? .null
                if let context {
                    absorb(result, of: context.method, session: context.sessionID, profile: context.profile)
                }
                resolve(id: id, with: .success(result))
            }
            return
        }
        if let method = frame["method"]?.stringValue, method != "event", let id = frame["id"]?.stringValue {
            requestSink.yield(ServerRequest(id: id, method: method, params: frame["params"] ?? .null))
            return
        }
        guard frame["method"]?.stringValue == "event", let params = frame["params"],
            let type = params["type"]?.stringValue
        else { return }
        let payload = params["payload"] ?? .null
        if type == "gateway.ready" {
            dialect = payload["session_authority"]?.boolValue == true ? .canonical : .legacy
            Self.log.info("Gateway ready, \(self.dialect.rawValue, privacy: .public) protocol")
            resolveReady(.success(GatewayReady(dialect: dialect, replayEpoch: payload["replay_epoch"])))
            return
        }
        if dialect == .canonical {
            for inbound in canonical.inbound(params) {
                switch inbound {
                case .event(let event): eventSink.yield(event)
                case .request(let request): requestSink.yield(request)
                }
            }
            return
        }
        eventSink.yield(
            GatewayEvent(
                type: type, sessionID: params["session_id"]?.stringValue, seq: params["seq"]?.intValue, payload: payload
            ))
    }

    private func resolve(id: Int, with result: Result<JSONValue, any Error>) {
        callContexts[id] = nil  // A call that timed out gets no reply to take it.
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if let timing = timings.removeValue(forKey: id) {
            let outcome: String
            switch result {
            case .success: outcome = "ok"
            case .failure(let error): outcome = "error=\(Trace.reason(error))"
            }
            // Pings are the link's round trip, worth a line each.
            let slow = timing.span.elapsed >= Trace.milliseconds(Self.slowCall)
            timing.span.end(outcome, logging: slow || outcome != "ok" || timing.method == "gateway.ping")
        }
        continuation.resume(with: result)
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
        Trace.event(
            "socket.closed",
            "reason=\(Trace.reason(error)) open_ms=\(Trace.milliseconds(since: openedAt)) quiet_ms=\(Trace.milliseconds(since: lastInbound)) failing=\(pending.count)"
        )
        for timing in timings.values { timing.span.end("error=\(Trace.reason(error))", logging: false) }
        timings.removeAll()
        socket.close()
        for continuation in pending.values { continuation.resume(throwing: error) }
        pending.removeAll()
        resolveReady(.failure(error))
        eventSink.finish()
        requestSink.finish()
        outbox.finish()
        writer?.cancel()
        for task in tasks { task.cancel() }
    }
}
