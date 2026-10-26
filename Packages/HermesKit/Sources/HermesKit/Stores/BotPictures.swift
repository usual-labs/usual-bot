import Foundation
import Observation

/// Agents' own pictures, set in the official app (uploaded or generated) and read from the gateway
/// with `profiles.get_asset`. An agent without one keeps the character the app draws for it.
@MainActor
@Observable
public final class BotPictures {
    /// A picture as last read: what the offline cache keeps.
    struct Stored: Codable, Equatable, Sendable {
        var revision: Int
        var data: Data
    }

    private(set) var stored: [Contact.ID: Stored] = [:]
    /// The revision this connection last asked the gateway about, by contact ID, so the roster's
    /// refresh every few seconds asks again only when an agent's look changed.
    @ObservationIgnored private var checked: [Contact.ID: Int] = [:]
    @ObservationIgnored private var checkedOn: ObjectIdentifier?

    init() {}

    /// The image file (PNG, JPEG or WebP) to show for an agent, or `nil` to draw its character.
    public func data(for contactID: Contact.ID) -> Data? { stored[contactID]?.data }

    /// Reads the pictures of `contacts` this connection hasn't read at their current revision, in
    /// the background, and forgets the pictures of agents that no longer have one. A new connection
    /// reads them all once more, which catches a picture changed without a new revision.
    func refresh(_ contacts: [Contact], on channel: JSONRPCChannel) {
        if checkedOn != ObjectIdentifier(channel) {
            checkedOn = ObjectIdentifier(channel)
            checked = [:]
        }
        let pictures = contacts.reduce(into: [Contact.ID: Contact.Picture]()) { $0[$1.id] = $1.picture }
        if stored.keys.contains(where: { pictures[$0] == nil }) {
            stored = stored.filter { pictures[$0.key] != nil }
        }
        for contact in contacts {
            guard let picture = contact.picture, checked[contact.id] != picture.revision else { continue }
            checked[contact.id] = picture.revision
            let profile = contact.details?.profile ?? contact.id
            Task { await load(contact.id, profile: profile, picture: picture, on: channel) }
        }
    }

    func restore(_ saved: [Contact.ID: Stored]) { stored = saved }

    func clear() {
        stored = [:]
        checked = [:]
        checkedOn = nil
    }

    private func load(_ id: Contact.ID, profile: String, picture: Contact.Picture, on channel: JSONRPCChannel) async {
        // A failed read waits for the next revision or connection rather than retrying every refresh.
        guard
            let result = try? await channel.call(
                "profiles.get_asset", params: ["name": .string(profile), "asset": "avatar"]),
            checked[id] == picture.revision
        else { return }
        guard result["found"]?.boolValue == true, let url = result["data"]?.stringValue,
            let data = MediaStore.decode(dataURL: url), picture.isPhoto || !Self.isDrawnFace(data)
        else {
            stored[id] = nil
            return
        }
        if stored[id]?.data != data { stored[id] = Stored(revision: picture.revision, data: data) }
    }

    /// The official app keeps a 160 × 160 PNG still of its drawn face as the avatar for its own use;
    /// uploads and generated pictures are 256 px. Such a still isn't a picture the user chose.
    static func isDrawnFace(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 24, data.prefix(8).elementsEqual(signature) else { return false }
        func uint32(at offset: Int) -> UInt32 {
            let start = data.startIndex + offset
            return data[start..<start + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        return uint32(at: 16) == 160 && uint32(at: 20) == 160
    }
}
