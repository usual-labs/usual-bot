import Foundation

/// What the app keeps of a chat between launches.
struct CachedThread: Codable, Equatable, Sendable {
    static let itemLimit = 60

    var state: ThreadState
    var lastViewed: Date?
    var unreadCount: Int
    /// Optional, so caches written before these existed still load.
    var sideQuestions: [SideQuestion]? = nil
    var backgroundTasks: [BackgroundTask]? = nil
    var backgroundResults: [BackgroundResult]? = nil
}

extension TranscriptItem {
    var isReply: Bool {
        if case .assistant = content { return true }
        return false
    }
}

extension ApprovalPrompt {
    /// The command shortened for one line of text.
    public var shortCommand: String {
        let line = command.split(whereSeparator: \.isNewline).first.map(String.init) ?? command
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }
}
