import Foundation
import Synchronization

/// Sends what you shared from the share extension itself, so it goes now rather than the next
/// time the app is open. Only when the extension can reach the gateway as the app does and the
/// chat is free; anything else, or anything it can't be sure of, stays in the shared folder for
/// the app (`AppModel.sendShared`). `docs/agents/decisions.md` says why each case waits.
public struct ShareSender: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// It's in the chat. The reply comes like any other.
        case sent
        /// It waits for the app, with why when there's more to say than that.
        case waiting(String?)
        /// It may be in the chat already, so the app shows it instead of sending it again.
        case unconfirmed
    }

    /// Files up to this size in all go from here. An extension gets about 120 MB on iPhone, and a
    /// file goes as base64 inside a JSON frame, so it's in memory several times over.
    static let fileLimit = 10 * 1024 * 1024
    /// Connecting and opening the chat; past this it's left for the app.
    static let openTimeout: Duration = .seconds(15)

    let container: ShareContainer
    let store: any TokenStore
    let http: any HTTPTransport
    let makeSocket: GatewayConnector.SocketFactory
    let openTimeout: Duration

    init(
        container: ShareContainer, store: any TokenStore, http: any HTTPTransport,
        makeSocket: @escaping GatewayConnector.SocketFactory, openTimeout: Duration = Self.openTimeout
    ) {
        self.container = container
        self.store = store
        self.http = http
        self.makeSocket = makeSocket
        self.openTimeout = openTimeout
    }

    /// The share extension's: the app's sign-in, over the system's network.
    public static func live(container: ShareContainer) -> ShareSender {
        ShareSender(
            container: container, store: KeychainTokenStore.forApp(), http: URLSession.shared,
            makeSocket: { URLSessionWebSocket(url: $0) })
    }

    /// Sends `item`, which `container` already holds, to `contact`. Sent, it's gone from the folder.
    public func send(_ item: SharedItem, to contact: Contact, roster: ShareRoster) async -> Outcome {
        guard let gateway = roster.address, gateway.fileName == item.gateway else { return .waiting(nil) }
        if roster.usesBuiltInTailscale == true, gateway.isTailnet {
            return .waiting(
                String(
                    localized:
                        "Usual Bot reaches your gateway through its built-in Tailscale, which runs only inside the app. Open Usual Bot to send it."
                ))
        }
        // Rooms go through the room service, which the app drives.
        guard contact.kind == .agent, size(of: item) <= Self.fileLimit,
            let tokens = try? store.load(for: gateway)
        else { return .waiting(nil) }

        let auth = AuthSession(gateway: gateway, tokens: tokens, store: store, http: http)
        let connector = GatewayConnector(auth: auth, makeSocket: makeSocket)
        let opening = Task { try await Self.open(contact, with: connector) }
        guard let opened = await Self.result(of: opening, within: openTimeout) else {
            opening.cancel()
            Task { if let (channel, _) = try? await opening.value { await channel.close() } }
            return .waiting(Self.unreachable)
        }
        let channel: JSONRPCChannel
        let chat: BotChat.Opened?
        do {
            (channel, chat) = try opened.get()
        } catch {
            return .waiting(Self.unreachable)
        }
        defer { Task { await channel.close() } }
        // The dashboard's socket can't tell a retry from a second message, so the app sends there.
        guard let chat else { return .waiting(nil) }
        // Now it would steer the reply or answer the question: the app waits for the chat instead.
        if chat.running || !chat.openRequests.isEmpty {
            return .waiting(
                String(
                    localized:
                        "\(contact.name) is busy right now. Usual Bot sends it once \(contact.name) is free, the next time it's open."
                ))
        }

        // From here a file may reach the chat even if this doesn't hear back. Sent again, it would
        // come twice, so if the extension ends early the app shows it rather than sending it.
        if !item.files.isEmpty {
            var marked = item
            marked.failure = String(
                localized: "This may be in the chat already. Check \(contact.name)'s chat before you try again.")
            try? container.save(marked)
        }
        do {
            var sent: [AttachmentRef] = []
            for name in item.files {
                let data = try Data(contentsOf: container.fileURL(name, of: item), options: .mappedIfSafe)
                sent.append(
                    try await ChatThread.upload(
                        .converting(name: name, data: data), sessionID: chat.sessionID, channel: channel))
            }
            // The item's ID: if the app sends it again, the gateway answers with this one's receipt.
            _ = try await channel.call(
                "prompt.submit",
                params: [
                    "session_id": .string(chat.sessionID), "text": .string(ChatThread.message(item.text, with: sent)),
                    "submission_id": .string(item.id.uuidString),
                ])
        } catch {
            return item.files.isEmpty ? .waiting(Self.unreachable) : .unconfirmed
        }
        container.remove(item.id)
        return .sent
    }

    private static let unreachable = String(
        localized: "Couldn't reach your gateway from here. Usual Bot sends it the next time it's open.")

    /// The socket, and the Bot's chat when the gateway can take a message from here.
    private static func open(_ contact: Contact, with connector: GatewayConnector) async throws
        -> (JSONRPCChannel, BotChat.Opened?)
    {
        let (channel, ready) = try await connector.connect()
        guard ready.dialect == .canonical else { return (channel, nil) }
        do {
            let chat = try await BotChat.open(
                profile: contact.id, knownID: contact.chatID, dialect: .canonical, on: channel)
            return (channel, chat)
        } catch {
            await channel.close()
            throw error
        }
    }

    private func size(of item: SharedItem) -> Int {
        item.files.reduce(0) { total, name in
            let path = container.fileURL(name, of: item).path
            return total + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? .max / 2)
        }
    }

    /// `task`'s result, or `nil` when it takes longer than `timeout`. Waiting on a task's value
    /// can't be cancelled, so this races the two instead.
    private static func result<T: Sendable>(of task: Task<T, any Error>, within timeout: Duration) async
        -> Result<T, any Error>?
    {
        let once = Once()
        return await withCheckedContinuation { continuation in
            let finish: @Sendable (Result<T, any Error>?) -> Void = { result in
                let first = once.done.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: result) }
            }
            Task {
                let result = await task.result
                finish(result)
            }
            Task {
                try? await Task.sleep(for: timeout)
                finish(nil)
            }
        }
    }
}

/// Lets only the first of two racing tasks finish.
private final class Once: Sendable {
    let done = Mutex(false)
}
