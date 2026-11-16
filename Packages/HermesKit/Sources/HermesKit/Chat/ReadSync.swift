import Foundation
import os

/// Shares how far each Bot Chat has been read between your devices, so a reply read on one stops
/// counting as unread on the others. Hermes keeps one read time per conversation
/// (`sessions.last_read_at`, the official app's Mark as Read and Mark as Unread); the unread count
/// stays this app's own.
///
/// Reading a chat here stamps the gateway's time on it, once per new reply; Mark as Unread sets it
/// to 0. The gateway sends `sessions.changed` when any conversation changes, without saying which,
/// so this device then looks again: first the small `mutation-snapshot`, then the chat's whole
/// record (system prompt included, about 90 KB) only when the revision moved, as every write moves it.
/// Chats unread here are looked at on every change; the rest, which only Mark as Unread elsewhere
/// can change, at most every `sweepInterval`. Rooms have no read time in Hermes, so they stay per
/// device.
@MainActor
final class ReadSync {
    struct Chat {
        let thread: ChatThread
        /// The Bot Chat's stored session, which the routes take.
        let storedID: String
        let profile: String
    }

    /// A chat's unread replies turned out to be read elsewhere; what was said about them can go.
    var cleared: ((Contact.ID) -> Void)?
    /// The gateway predates the read time (Hermes before August 2026). Asked again on reconnecting.
    private(set) var isUnsupported = false

    private let auth: @MainActor () -> AuthSession?
    private let chats: @MainActor () -> [Chat]
    /// Each chat's revision when this device last knew its read time, by stored session.
    private var revisions: [String: Int] = [:]
    /// Chats that may have been read elsewhere since this device last looked.
    private var stale: Set<Contact.ID> = []
    private var writing: Set<String> = []
    private var isLooking = false
    /// When chats read here were last looked at.
    private var lastSweep: ContinuousClock.Instant?
    var sweepInterval: Duration = .seconds(30)
    private var looksAgain = false
    /// What's under way, for `settled()`.
    private var work: [Task<Void, Never>] = []

    private static let log = Logger(subsystem: "UsualBot", category: "read")

    init(auth: @escaping @MainActor () -> AuthSession?, chats: @escaping @MainActor () -> [Chat]) {
        self.auth = auth
        self.chats = chats
    }

    // MARK: - Reading elsewhere

    /// A new link, or `sessions.changed`: any chat may have been read elsewhere meanwhile.
    func somethingChanged() {
        stale.formUnion(chats().map(\.thread.contactID))
        look()
    }

    /// Looks up the read time of each chat that may have changed. One read here stays due until
    /// the next sweep, or until it has something unread.
    func look() {
        guard !isUnsupported else { return }
        guard !isLooking else {
            looksAgain = true
            return
        }
        let sweeps = lastSweep.map { $0.duration(to: .now) >= sweepInterval } ?? true
        let due = chats().filter { chat in
            stale.contains(chat.thread.contactID) && !writing.contains(chat.storedID)
                && (sweeps || chat.thread.unreadCount > 0 || chat.thread.isMarkedUnread)
        }
        guard !due.isEmpty, let auth = auth() else { return }
        if sweeps { lastSweep = .now }
        stale.subtract(due.map(\.thread.contactID))
        isLooking = true
        run { [self] in
            for chat in due where !isUnsupported { await lookUp(chat, auth: auth) }
            isLooking = false
            if looksAgain {
                looksAgain = false
                look()
            }
        }
    }

    private func lookUp(_ chat: Chat, auth: AuthSession) async {
        let known = revisions[chat.storedID]
        do {
            let revision = try await snapshot(of: chat, auth: auth)
            guard revision != known else { return }
            let record = try await auth.json(
                Record.self, path: Self.path(chat) + "?profile=\(Self.escape(chat.profile))")
            guard record.hasReadTime else {
                isUnsupported = true
                return
            }
            // A write from here meanwhile knows better than what was read before it: look again after.
            guard revisions[chat.storedID] == known, !writing.contains(chat.storedID) else {
                stale.insert(chat.thread.contactID)
                return
            }
            revisions[chat.storedID] = revision
            let thread = chat.thread
            switch record.lastReadAt {
            case 0:
                // Hermes's Mark as Unread, from here or elsewhere. It has no count.
                thread.adoptUnread()
            case let readAt?:
                let wasUnread = thread.unreadCount > 0 || thread.isMarkedUnread
                thread.adoptRead(at: Date(timeIntervalSince1970: readAt))
                if wasUnread, thread.unreadCount == 0, !thread.isMarkedUnread { cleared?(thread.contactID) }
            case nil:
                break  // never marked, which Hermes counts as read
            }
            // Marked here, but the write didn't get there.
            if thread.isMarkedUnread, !thread.unreadOnGateway { markUnread(thread.contactID) }
        } catch {
            note(error)
        }
    }

    // MARK: - Reading here

    /// You've seen `id`'s replies: tells the gateway, unless it already knows them read. Not while
    /// the chat is marked unread.
    func markRead(_ id: Contact.ID) {
        guard !isUnsupported, let chat = chat(id), !chat.thread.isMarkedUnread,
            !writing.contains(chat.storedID), let auth = auth()
        else { return }
        let newest = chat.thread.newestUnreadable
        let isNew = newest.map { $0 > chat.thread.readOnGateway ?? .distantPast } ?? false
        guard isNew || chat.thread.unreadOnGateway else { return }
        writing.insert(chat.storedID)
        run { [self] in
            let saved = await write(chat, unread: false, auth: auth)
            writing.remove(chat.storedID)
            guard saved else { return }
            chat.thread.unreadOnGateway = false
            if let newest { chat.thread.readOnGateway = max(chat.thread.readOnGateway ?? .distantPast, newest) }
            settle(chat)
        }
    }

    /// You marked `id` unread: tells the gateway, so it's unread on your other devices and in the
    /// official app too.
    func markUnread(_ id: Contact.ID) {
        guard !isUnsupported, let chat = chat(id), chat.thread.isMarkedUnread, !chat.thread.unreadOnGateway,
            !writing.contains(chat.storedID), let auth = auth()
        else { return }
        writing.insert(chat.storedID)
        run { [self] in
            let saved = await write(chat, unread: true, auth: auth)
            writing.remove(chat.storedID)
            guard saved else { return }
            chat.thread.unreadOnGateway = true
            settle(chat)
        }
    }

    /// After a write: what changed meanwhile gets its own, such as a chat marked or opened, or a
    /// reply that came in while you watched. A failed write waits for the next change.
    private func settle(_ chat: Chat) {
        let id = chat.thread.contactID
        if chat.thread.isMarkedUnread {
            if !chat.thread.unreadOnGateway { markUnread(id) }
        } else if chat.thread.unreadCount == 0 {
            markRead(id)
        }
        // A look skips a chat while it's written.
        if !writing.contains(chat.storedID), stale.contains(id) { look() }
    }

    private func chat(_ id: Contact.ID) -> Chat? {
        chats().first { $0.thread.contactID == id }
    }

    /// `PATCH /api/sessions/{id}` with `unread`, at the chat's current revision. A write elsewhere
    /// can move the revision in between; that one is tried once more.
    private func write(_ chat: Chat, unread: Bool, auth: AuthSession) async -> Bool {
        var known = revisions[chat.storedID]
        for _ in 0..<2 {
            do {
                let revision: Int
                if let known {
                    revision = known
                } else {
                    revision = try await snapshot(of: chat, auth: auth)
                }
                let mark = Mark(
                    unread: unread, requestId: UUID().uuidString.lowercased(), expectedRevision: revision,
                    profile: chat.profile)
                let receipt = try await auth.json(Receipt.self, path: Self.path(chat), method: "PATCH", body: mark)
                revisions[chat.storedID] = receipt.revision
                return true
            } catch GatewayError.http(status: 409, "revision_conflict") {
                known = nil
            } catch {
                note(error)
                return false
            }
        }
        return false
    }

    private func run(_ operation: @escaping @MainActor () async -> Void) {
        work.removeAll { $0.isCancelled }
        work.append(Task { await operation() })
    }

    /// Waits for every request so far, and those they lead to, for tests.
    func settled() async {
        while !work.isEmpty {
            let current = work
            work = []
            for task in current { await task.value }
        }
    }

    // MARK: - The gateway

    private func snapshot(of chat: Chat, auth: AuthSession) async throws -> Int {
        let path = Self.path(chat) + "/mutation-snapshot?profile=\(Self.escape(chat.profile))"
        return try await auth.json(Snapshot.self, path: path).runtimeRevision
    }

    /// A gateway without the routes or the `unread` field turns this off; anything else is
    /// temporary and the next change or reply tries again.
    private func note(_ error: any Error) {
        if case GatewayError.http(let status, _) = error, [400, 404, 405, 422].contains(status) {
            isUnsupported = true
        }
        Self.log.notice("Read state not shared: \(AppModel.describe(error), privacy: .public)")
    }

    /// Forgets everything on signing out or switching gateways.
    func reset() {
        revisions = [:]
        stale = []
        lastSweep = nil
        isUnsupported = false
    }

    /// Reconnected: the gateway may have been updated, so it's asked again whether it keeps read
    /// times. A revision still says whether a chat changed, so they're kept.
    func reconnected() {
        isUnsupported = false
        lastSweep = nil
    }

    private static func path(_ chat: Chat) -> String {
        "/api/sessions/\(escape(chat.storedID))"
    }

    private static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? text
    }

    private struct Snapshot: Decodable {
        let runtimeRevision: Int
    }

    /// The parts of `GET /api/sessions/{id}` used here. `last_read_at` is null until the chat was
    /// first marked; a gateway that leaves the key out doesn't keep read times at all.
    private struct Record: Decodable {
        let lastReadAt: Double?
        let hasReadTime: Bool

        private enum CodingKeys: String, CodingKey { case lastReadAt }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasReadTime = container.contains(.lastReadAt)
            lastReadAt = try? container.decodeIfPresent(Double.self, forKey: .lastReadAt)
        }
    }

    private struct Mark: Encodable, Sendable {
        let unread: Bool
        let requestId: String
        let expectedRevision: Int
        let profile: String
    }

    private struct Receipt: Decodable {
        let revision: Int
    }
}
