import Foundation

extension AppModel {
    /// You tapped a notification about `chat`: the time until it's ready is a `resume`, as coming
    /// back to the app is.
    public func notificationOpened(_ chat: Contact.ID, kind: String?) {
        Trace.event(
            "notification.opened",
            Trace.fields("chat=\(Trace.tag(chat))", kind.map { "kind=\($0)" } ?? "", "link=\(link.traceName)"))
        resumedAt = resumedAt ?? .now
    }

    /// A chat finished opening. The one on screen, after you came back, ends the `resume`.
    func traceOpened(_ id: Contact.ID) {
        guard let resumedAt, isShown(id) else { return }
        self.resumedAt = nil
        Trace.event(
            "resume.ready",
            "chat=\(Trace.tag(id)) ms=\(Trace.milliseconds(since: resumedAt)) ready=\(threads[id]?.isAttached == true)")
    }
}

extension AppModel.Link {
    var traceName: String {
        switch self {
        case .connecting: "connecting"
        case .online: "online"
        case .offline: "offline"
        }
    }

    var isOnline: Bool {
        if case .online = self { return true }
        return false
    }
}
