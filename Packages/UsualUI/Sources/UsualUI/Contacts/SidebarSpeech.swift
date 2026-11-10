import HermesKit

/// What VoiceOver says for the sidebar. A row's dot, count and moving avatar are each one fact,
/// so they're spoken as words rather than left to whichever child views SwiftUI combines.
enum SidebarSpeech {
    /// "Forge, pinned, needs you, 2 unread, Needs your OK…, 10:44 AM".
    static func row(_ contact: Contact, preview: String, stamp: String?) -> String {
        let pinned = contact.isPinned ? [String(localized: "pinned")] : []
        let facts = facts(activity: contact.activity, unreadCount: contact.unreadCount)
        return ([contact.name] + pinned + facts + [preview, stamp ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// A heading's value. Folded, it says what its hidden rows would, as its indicator shows it.
    static func section(_ block: SidebarBlock, isFolded: Bool) -> String {
        guard isFolded else { return String(localized: "Open") }
        let facts = facts(activity: block.needsYou ? .needsYou : .idle, unreadCount: block.unreadCount)
        return ([String(localized: "Folded")] + facts).joined(separator: ", ")
    }

    private static func facts(activity: Contact.Activity, unreadCount: Int) -> [String] {
        var facts: [String] = []
        switch activity {
        case .needsYou: facts.append(String(localized: "needs you"))
        case .working: facts.append(String(localized: "working"))
        case .idle: break
        }
        if unreadCount > 0 { facts.append(String(localized: "\(unreadCount) unread")) }
        return facts
    }
}
