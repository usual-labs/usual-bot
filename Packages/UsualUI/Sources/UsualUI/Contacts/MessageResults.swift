import HermesKit
import SwiftUI

/// A search result chosen: open its chat or room and show the message.
struct MessageJump: Equatable {
    let id = UUID()
    let contactID: Contact.ID
    let itemID: Int
}

/// Searching messages, from the app model: what the device holds at once, and what the gateway
/// finds in older history as it answers.
struct MessageSearching {
    /// Matches for a query, the gateway's among them once they arrive.
    var hits: (String) -> [MessageHit] = { _ in [] }
    var status: (String) -> MessageSearchStatus = { _ in .idle }
    /// Asks the gateway once typing pauses; a new query replaces the last, an empty one ends it.
    var lookUp: (String) -> Void = { _ in }
    /// Where a result is, loading its chat first when the gateway found it.
    var locate: (MessageHit) async -> MessageLocation = { .item($0.itemID ?? 0) }
}

/// Under the results: the gateway is still searching, or can't be asked.
struct MessageSearchStatusLine: View {
    let status: MessageSearchStatus

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching older messages on the gateway…")
            }
            .modifier(StatusLook())
        case .offline:
            Text("Not connected, so only messages on this device are searched.")
                .modifier(StatusLook())
        }
    }

    private struct StatusLook: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
        }
    }
}

/// Over the chat while search opens a message the gateway found: finding it, or why it can't.
struct FindingNotice: View {
    enum State: Equatable {
        case finding
        case unavailable(String)
    }

    let state: State
    let dismiss: () -> Void

    /// Under the name at the top of a Mac chat; under the navigation bar on iPhone.
    #if os(macOS)
        static let top: CGFloat = 64
    #else
        static let top: CGFloat = 8
    #endif

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .finding:
                ProgressView().controlSize(.small)
                Text("Loading the chat to find the message…")
            case .unavailable(let reason):
                Text(reason)
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.clickable)
                    .frame(minWidth: 28, minHeight: 28)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.ink)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Theme.pane, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(contact.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Text(hit.when)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryInk.opacity(0.75))
                }
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

extension View {
    /// Shows `state` at the top of a chat while search loads it to find a message.
    func findingNotice(_ state: FindingNotice.State?, dismiss: @escaping () -> Void) -> some View {
        overlay(alignment: .top) {
            if let state {
                FindingNotice(state: state, dismiss: dismiss)
                    .padding(.top, FindingNotice.top)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: state)
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

    /// When it was said; for a message the gateway found, only that it's older than what's loaded.
    var when: String {
        if let date { return ContactRow.stamp(for: date) }
        return isEarlier ? String(localized: "Earlier") : ""
    }

    /// One phrase for VoiceOver: "Atlas, message: You: …, Yesterday".
    func spokenLabel(in chat: String) -> String {
        let when = isEarlier ? String(localized: "earlier message, found on the gateway") : when
        return when.isEmpty
            ? String(localized: "\(chat), message: \(authorPrefix)\(snippet)")
            : String(localized: "\(chat), message: \(authorPrefix)\(snippet), \(when)")
    }
}
