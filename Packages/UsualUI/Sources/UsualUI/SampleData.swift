import Foundation
import HermesKit

/// Placeholder contacts for previews, and for the app until it can connect to a gateway.
public enum SampleData {
    public static func contacts(now: Date = .now) -> [Contact] {
        [
            Contact(
                id: "hermes", name: "Hermes", tint: "#6E7BFF", preview: "Needs your OK to push",
                lastActive: now.addingTimeInterval(-120), activity: .needsYou),
            Contact(
                id: "scout", name: "Scout", tint: "#1FA971", preview: "Reading 14 new issues…",
                lastActive: now.addingTimeInterval(-10), activity: .working),
            Contact(
                id: "launch-room", name: "Launch room", kind: .room(memberIDs: ["writer", "scout"]),
                preview: "Writer: Draft is ready, pick a headline", lastActive: now.addingTimeInterval(-300),
                unreadCount: 2),
            Contact(
                id: "ops", name: "Ops", tint: "#F2A30F", preview: "All 3 servers healthy, backups verified",
                lastActive: now.addingTimeInterval(-4 * 3600)),
            Contact(
                id: "writer", name: "Writer", tint: "#F0565E", preview: "Two headline options for the post",
                lastActive: now.addingTimeInterval(-2 * 86_400)),
        ]
    }
}
