import Foundation

#if os(macOS)
    import CoreGraphics
#endif

/// Whether you've stepped away from a device that still has the app in front. A Mac left with its
/// window focused would otherwise keep your iPhone's notifications waiting. An iPhone with the
/// app open is in your hand: it locks itself when it isn't.
enum UserIdle {
    static let after: TimeInterval = 60

    #if os(macOS)
        /// `kCGAnyInputEventType`, which Swift doesn't name.
        private static let anyInput = CGEventType(rawValue: ~0)!
    #endif

    static var isAway: Bool {
        #if os(macOS)
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) > after
        #else
            false
        #endif
    }
}
