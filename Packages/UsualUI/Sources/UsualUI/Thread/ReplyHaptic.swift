import HermesKit
import SwiftUI

/// A soft tap on the iPhone as a Bot's message lands in the chat or room on screen: each message
/// on the way to the reply, and the reply itself. Not on the Mac, where a trackpad tap under a
/// resting hand would be a surprise.
struct ReplyHaptic: ViewModifier {
    /// The Bots' messages so far.
    let replies: Int
    /// A reloaded transcript counts afresh: its messages aren't arriving.
    var load = 0
    @Environment(\.conversationShown) private var shown

    func body(content: Content) -> some View {
        #if os(iOS)
            content.sensoryFeedback(
                .impact(flexibility: .soft, intensity: 0.5), trigger: Count(load: load, replies: replies)
            ) { old, new in
                shown && old.load == new.load && new.replies > old.replies
            }
        #else
            content
        #endif
    }

    private struct Count: Equatable {
        let load: Int
        let replies: Int
    }
}

extension TranscriptItem {
    /// A Bot's message to you: in a chat, or a member's in a room.
    var isBotReply: Bool {
        switch content {
        case .assistant, .member: true
        default: false
        }
    }
}
