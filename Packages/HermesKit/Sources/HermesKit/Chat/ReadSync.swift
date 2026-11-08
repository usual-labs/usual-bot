import Foundation
import os

/// Shares how far each Bot Chat has been read between your devices, so a reply read on one stops
/// counting as unread on the others. Hermes keeps one read time per conversation
/// (`sessions.last_read_at`, the official app's Mark as Read); the unread count stays this app's own.
///
/// Reading a chat here stamps the gateway's time on it, once per new reply. The gateway sends
/// `sessions.changed` when any conversation changes, without saying which, so this device then looks
/// again at the chats it counts unread: first the small `mutation-snapshot`, then the chat's whole
/// record (system prompt included, about 90 KB) only when the revision moved, as every write moves it.
/// Rooms have no read time in Hermes, so they stay per device.
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

    /// Looks up the read time of each chat unread here that may have changed. A chat with nothing
    /// unread stays due, so it's looked at once it has something.
    func look() {
        guard !isUnsupported else { return }
        guard !isLooking else {
            looksAgain = true
            return
        }
        let due = chats().filter { stale.contains($0.thread.contactID) && $0.thread.unreadCount > 0 }
        guard !due.isEmpty, let auth = auth() else { return }
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
        do {
            let revision = try await snapshot(of: chat, auth: auth)
            guard revision != revisions[chat.storedID] else { return }
            let record = try await auth.json(
                Record.self, path: Self.path(chat) + "?profile=\(Self.escape(chat.profile))")
            guard record.hasReadTime else {
                isUnsupported = true
                return
            }
            revisions[chat.storedID] = revision
            // 0 is the official app's Mark as Unread, which leaves this device's count alone.
            guard let readAt = record.lastReadAt, readAt > 0 else { return }
            let thread = chat.thread
            let before = thread.unreadCount
            thread.adoptRead(at: Date(timeIntervalSince1970: readAt))
            if before > 0, thread.unreadCount == 0 { cleared?(thread.contactID) }
        } catch {
            note(error)
        }
    }

    // MARK: - Reading here

    /// You've seen `id`'s replies: tells the gateway, unless it already knows them read.
    func markRead(_ id: Contact.ID) {
        guard !isUnsupported, let chat = chats().first(where: { $0.thread.contactID == id }),
            let newest = chat.thread.newestUnreadable, newest > chat.thread.readOnGateway ?? .distantPast,
            !writing.contains(chat.storedID), let auth = auth()
        else { return }
        writing.insert(chat.storedID)
        run { [self] in
            let saved = await write(chat, auth: auth)
            writing.remove(chat.storedID)
            guard saved else { return }
            chat.thread.readOnGateway = max(chat.thread.readOnGateway ?? .distantPast, newest)
            // A reply that came in meanwhile, while you watched, gets its own write.
            if chat.thread.isVisible { markRead(id) }
        }
    }

    /// `PATCH /api/sessions/{id}` with `unread: false`, at the chat's current revision. A write
    /// elsewhere can move the revision in between; that one is tried once more.
    private func write(_ chat: Chat, auth: AuthSession) async -> Bool {
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
                    unread: false, requestId: UUID().uuidString.lowercased(), expectedRevision: revision,
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

    /// Forgets everything on signing out or reconnecting, as the gateway may have been updated.
    func reset() {
        revisions = [:]
        stale = []
        isUnsupported = false
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
