import HermesKit
import SwiftUI

/// What VoiceOver says about changes in the open conversation that don't move its focus.
enum TranscriptAnnouncement {
    /// Search showed this message.
    static func found(_ item: TranscriptItem) -> String {
        switch item.content {
        case .user(let text), .assistant(let text), .member(_, let text):
            // Plain words: no quote, attachment or `MEDIA:` lines, no Markdown marks.
            let excerpt = QuotedMessage(author: "", text: QuotedMessage.split(text).text).excerpt
            return excerpt.isEmpty ? String(localized: "Found the message") : String(localized: "Found: \(excerpt)")
        default:
            return String(localized: "Found the message")
        }
    }

    /// Spoken before what's already being said, such as the chat that just opened.
    static func post(_ text: String) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }
}
