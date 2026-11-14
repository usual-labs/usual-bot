import Foundation

/// The lock the app and its share extension take before renewing a sign-in, so neither renews
/// with a refresh token the other already spent (`AuthSession`). It's `flock` on a file in their
/// App Group: the system lets go when a process ends, so a crash can't leave it held.
public struct RefreshLock: Sendable {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Holding the lock until `release()`.
    public final class Held: Sendable {
        private let descriptor: Int32

        fileprivate init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        public func release() {
            flock(descriptor, LOCK_UN)
            close(descriptor)
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
        return Held(descriptor: descriptor)
    }
}
