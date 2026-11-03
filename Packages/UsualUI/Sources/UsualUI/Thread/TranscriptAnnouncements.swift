import HermesKit
import SwiftUI

/// What VoiceOver says about changes in the open conversation that don't move its focus.
enum TranscriptAnnouncement {
    /// Search showed this message.
    static func found(_ item: TranscriptItem) -> String {
        switch item.content {
        case .user(let text), .assistant(let text), .member(_, let text):
            // Plain words: no quote, attachments, files, headings' or lists' marks.
            let body = QuotedMessage.split(AttachmentRef.split(text).text).text
            let words = MarkdownBlock.parse(body).compactMap { block -> String? in
                switch block {
                case .paragraph(let text), .heading(_, let text), .listItem(_, _, let text), .quote(let text):
                    String(text.characters)
                default: nil
                }
            }
            let excerpt = words.joined(separator: " ")
            guard !excerpt.isEmpty else { return String(localized: "Found the message") }
            return String(localized: "Found: \(excerpt.count > 120 ? excerpt.prefix(120) + "…" : excerpt)")
        default:
            return String(localized: "Found the message")
        }
    }

    /// A card asking you for something came into the open conversation. Answering one says nothing.
    static func appeared(from old: WaitingCards, to new: WaitingCards, agent: String) -> String? {
        if new.approvals > old.approvals { return String(localized: "\(agent) wants your OK to run a command") }
        if new.questions > old.questions { return String(localized: "\(agent) has a question for you") }
        if new.secrets > old.secrets { return String(localized: "\(agent) needs a secret") }
        if new.vault > old.vault { return String(localized: "\(agent) needs a password, login or code") }
        if new.connections > old.connections { return String(localized: "\(agent) wants you to connect apps") }
        return nil
    }

    /// Spoken before what's already being said, such as the chat that just opened.
    static func post(_ text: String) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }
}

/// How many cards of each kind wait for you in a conversation.
struct WaitingCards: Equatable {
    var approvals = 0
    var questions = 0
    var secrets = 0
    var vault = 0
    var connections = 0
}
