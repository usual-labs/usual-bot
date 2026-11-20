import Foundation
import Synchronization

/// The lock the app and its share extension take before renewing a sign-in, so neither renews
/// with a refresh token the other already spent (`AuthSession`). It's `flock` on a file in their
/// App Group: the system lets go when a process ends, so a crash can't leave it held.
///
/// iOS ends a process suspended while it holds a lock in a shared container (0xdead10cc), and a
/// renewal can still be waiting on the gateway when the app leaves the screen. So the lock asks
/// to stay awake while it's held, and lets go if iOS won't wait any longer.
public struct RefreshLock: Sendable {
    /// Asks the system to keep the process running, calling `expired` when it won't any more;
    /// the closure it returns says the work is done.
    public typealias StayAwake = @Sendable (_ expired: @escaping @Sendable () -> Void) -> @Sendable () -> Void

    let url: URL
    let stayAwake: StayAwake

    public init(url: URL, stayAwake: @escaping StayAwake = RefreshLock.processActivity) {
        self.url = url
        self.stayAwake = stayAwake
    }

    /// Works in the app and in an extension, where there's no `UIApplication`. The activity holds
    /// a thread until it's done, which is one request at most. A Mac doesn't suspend apps like this.
    public static let processActivity: StayAwake = { expired in
        #if os(iOS)
            let done = DispatchSemaphore(value: 0)
            ProcessInfo.processInfo.performExpiringActivity(withReason: "Renewing the gateway sign-in") { expiring in
                if expiring { expired() } else { done.wait() }
            }
            return { done.signal() }
        #else
            return {}
        #endif
    }

    /// Holding the lock until `release()`, or until the system won't keep the process awake.
    public final class Held: Sendable {
        private struct State {
            var descriptor: Int32?
            var done: (@Sendable () -> Void)?
        }

        private let state: Mutex<State>

        fileprivate init(descriptor: Int32) {
            state = Mutex(State(descriptor: descriptor))
        }

        /// Expiry can come before `stayAwake` has returned, so `done` may arrive after release.
        fileprivate func awake(until done: @escaping @Sendable () -> Void) {
            let released = state.withLock { state in
                if state.descriptor == nil { return true }
                state.done = done
                return false
            }
            if released { done() }
        }

        /// Safe to call more than once, and from any thread.
        public func release() {
            let (descriptor, done) = state.withLock { state in
                defer { state = State() }
                return (state.descriptor, state.done)
            }
            if let descriptor {
                flock(descriptor, LOCK_UN)
                close(descriptor)
            }
            done?()
        }
    }

    /// Waits for the lock. A renewal takes one request, so a lock held past `timeout` means
    /// something's wrong; the renewal then fails without signing out, and the next one tries again.
    public func acquire(timeout: Duration = .seconds(45)) async throws -> Held {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw GatewayError.timedOut }
        let deadline = ContinuousClock.now + timeout
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ContinuousClock.now < deadline, !Task.isCancelled else {
                close(descriptor)
                throw GatewayError.timedOut
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let held = Held(descriptor: descriptor)
        held.awake(until: stayAwake { held.release() })
        return held
    }
}
