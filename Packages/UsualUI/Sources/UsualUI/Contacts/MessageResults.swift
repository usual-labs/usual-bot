import HermesKit
import SwiftUI

/// A search result chosen: open its chat or room and show the message.
struct MessageJump: Equatable {
    let id = UUID()
    let contactID: Contact.ID
    let itemID: Int

    init(_ hit: MessageHit) {
        contactID = hit.contactID
        itemID = hit.itemID
    }
}

extension EnvironmentValues {
    /// The transcript item a search just jumped to, highlighted for a moment.
    @Entry var highlightedItem: Int?
}

/// A message found by search: the chat's avatar and name, and a line of the message with the
/// words you typed in bold.
struct MessageHitRow: View {
    let hit: MessageHit
    let contact: Contact
    let members: [Contact]
    var avatarSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 12) {
            switch contact.kind {
            case .agent: AgentAvatar(contact: contact, size: avatarSize)
            case .room: RoomAvatar(members: members, size: avatarSize)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(hit.styledSnippet(size: 12.5))
                    .foregroundStyle(Theme.secondaryInk)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(hit.spokenLabel(in: contact.name)))
    }
}

extension MessageHit {
    /// Who wrote it, before the snippet; nothing for the chat's own agent, whose name is above.
    var authorPrefix: String {
        switch author {
        case .you: String(localized: "You: ")
        case .agent: ""
        case .member(let name): "\(name): "
        }
    }

    /// The snippet with its matches in bold. Each run sets its own font, since `Text` ignores a
    /// strong intent once the view sets one.
    func styledSnippet(size: CGFloat) -> AttributedString {
        var styled = AttributedString(authorPrefix)
        styled.font = .system(size: size)
        var cursor = snippet.startIndex
        for match in matches where match.lowerBound >= cursor {
            styled += run(snippet[cursor..<match.lowerBound], size: size, bold: false)
            styled += run(snippet[match], size: size, bold: true)
            cursor = match.upperBound
        }
        styled += run(snippet[cursor...], size: size, bold: false)
        return styled
    }

    private func run(_ text: Substring, size: CGFloat, bold: Bool) -> AttributedString {
        var run = AttributedString(String(text))
        run.font = .system(size: size, weight: bold ? .semibold : .regular)
        if bold { run.foregroundColor = Theme.ink }
        return run
    }

    /// One phrase for VoiceOver: "Atlas, message: You: …".
    func spokenLabel(in chat: String) -> String {
        String(localized: "\(chat), message: \(authorPrefix)\(snippet)")
    }
}
