import CryptoKit
import Foundation
import Network
import os

/// Timings for finding where the app waits: connecting, uploads, opening chats, a message on its
/// way from one of your devices to another. Read them in Console.app (`subsystem:UsualBot
/// category:perf`, the Mac's own or a paired iPhone's) or as intervals in Instruments.
///
/// Every field is logged public, so callers put in only durations, sizes, counts, method names,
/// random IDs and `tag`s: never words, names, paths or tokens. Lines are `notice`s, the lowest level
/// iOS keeps for `log collect`.
public enum Trace {
    static let log = Logger(subsystem: "UsualBot", category: "perf")
    static let signposter = OSSignposter(subsystem: "UsualBot", category: "perf")

    /// When the process first touched `Trace`; the app touches it as it starts.
    public static let launched = ContinuousClock.now

    /// Something happened: `name` and its `key=value` fields.
    public static func event(_ name: String, _ fields: String = "") {
        let line = fields.isEmpty ? name : name + " " + fields
        log.notice("\(line, privacy: .public)")
    }

    /// Starts timing `name`, an interval in Instruments; `Span.end` logs how long it took.
    public static func begin(_ name: StaticString, _ fields: String = "") -> Span {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID(), "\(fields, privacy: .public)")
        return Span(name: name, state: state, fields: fields)
    }

    /// A short stand-in for a chat or a gateway, the same on every device, so two devices' logs
    /// line up without naming it.
    public static func tag(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    public static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    public static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        milliseconds(.now - start)
    }

    /// `ms=…` from `start`, or nothing without one.
    static func since(_ start: ContinuousClock.Instant?, _ key: String = "ms") -> String {
        start.map { "\(key)=\(milliseconds(since: $0))" } ?? ""
    }

    /// Logs each change of the route to the network, to line up with the gateway link dropping.
    /// Watches only: reconnecting stays the link's own business.
    public static func watchNetwork() {
        NetworkWatch.shared.start()
    }

    /// What went wrong, as a code without the gateway's words: `timedOut`, `http-502`, `url-1001`.
    public static func reason(_ error: any Error) -> String {
        switch error {
        case let error as GatewayError:
            switch error {
            case .unreachable: "unreachable"
            case .http(let status, _): "http-\(status)"
            case .invalidResponse: "invalidResponse"
            case .signInUnsupported: "signInUnsupported"
            case .signInRequired: "signInRequired"
            case .signInFailed: "signInFailed"
            case .cancelled: "cancelled"
            case .timedOut: "timedOut"
            case .disconnected: "disconnected"
            case .rpc(let code, _): "rpc\(code)"
            }
        case let error as CanonicalRefusal: "refused-\(error.reason)"
        case let error as URLError: "url\(error.code.rawValue)"
        case is CancellationError: "cancelled"
        default: String(describing: type(of: error))
        }
    }

    private static let logged = OSAllocatedUnfairLock(initialState: Set<String>())

    /// `event`, only the first time this process logs `name`: steps of a launch.
    public static func first(_ name: String, _ fields: String = "") {
        guard logged.withLock({ $0.insert(name).inserted }) else { return }
        event(name, Trace.fields(fields, since(launched, "since_launch_ms")))
    }

    public static func fields(_ parts: String...) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// One timed step from `Trace.begin`.
public struct Span: @unchecked Sendable {
    // @unchecked: the interval state is never changed after it's made.
    let name: StaticString
    let state: OSSignpostIntervalState
    let fields: String
    let start = ContinuousClock.now

    public var elapsed: Int { Trace.milliseconds(since: start) }

    /// Logs the step's time with `result`, e.g. `ok` or `error=…`. `logging: false` only closes
    /// its interval, for steps worth a line only when they're slow.
    public func end(_ result: String = "", logging: Bool = true) {
        Trace.signposter.endInterval(name, state, "\(result, privacy: .public)")
        if logging { Trace.event("\(name)", Trace.fields("ms=\(elapsed)", fields, result)) }
    }
}

private final class NetworkWatch: @unchecked Sendable {
    // @unchecked: `started` is only touched on the main thread, and `last` only on the monitor's queue.
    static let shared = NetworkWatch()
    private let monitor = NWPathMonitor()
    private var started = false
    /// The last line logged: the monitor also calls back for changes that leave it the same.
    private var last: String?

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [self] path in
            let via: String =
                if path.usesInterfaceType(.wifi) {
                    "wifi"
                } else if path.usesInterfaceType(.cellular) {
                    "cellular"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    "ethernet"
                } else if path.usesInterfaceType(.other) {
                    "other"
                } else {
                    "none"
                }
            let status: String =
                switch path.status {
                case .satisfied: "up"
                case .unsatisfied: "down"
                case .requiresConnection: "waiting"
                @unknown default: "unknown"
                }
            let line =
                "status=\(status) via=\(via) interfaces=\(path.availableInterfaces.count) expensive=\(path.isExpensive) constrained=\(path.isConstrained)"
            guard line != last else { return }
            last = line
            Trace.event("network.path", line)
        }
        monitor.start(queue: DispatchQueue(label: "UsualBot.network-watch"))
    }
}
