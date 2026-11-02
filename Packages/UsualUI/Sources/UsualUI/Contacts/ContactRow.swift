import HermesKit
import SwiftUI

/// One sidebar row: avatar, name, preview and an unread count, with a dot on the avatar when the
/// agent needs you. No time of last activity, as in Grok. Compact, in the narrow window's rail, it's
/// the avatar alone with the count as a badge too.
struct ContactRow: View {
    let contact: Contact
    /// Resolved members when `contact` is a room; empty for agents.
    let members: [Contact]
    var compact = false

    var body: some View {
        if compact {
            avatar
                .overlay(alignment: .topTrailing) { badge.offset(x: 6, y: -4) }
                .padding(.vertical, 4)
                .help(contact.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityName))
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            avatar
                .overlay(alignment: .topTrailing) {
                    if contact.activity == .needsYou { NeedsYouDot().offset(x: 3, y: -2) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(previewText)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ContactIndicator(needsYou: false, unreadCount: contact.unreadCount)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var avatar: some View {
        switch contact.kind {
        case .agent: AgentAvatar(contact: contact, size: avatarSize)
        case .room: RoomAvatar(members: members, size: avatarSize)
        }
    }

    /// iPhone rows and the Mac's rail keep the larger avatar; the Mac's rows have the name to go by.
    private var avatarSize: CGFloat {
        #if os(macOS)
            compact ? 44 : 36
        #else
            44
        #endif
    }

    /// The rail's corner badge: the unread count, or a dot when the agent needs you.
    @ViewBuilder private var badge: some View {
        if contact.activity == .needsYou {
            NeedsYouDot()
        } else if contact.unreadCount > 0 {
            Text(contact.unreadCount, format: .number)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.primaryInk)
                .padding(.horizontal, 4)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(Theme.primary))
                .overlay(Capsule().strokeBorder(Theme.window, lineWidth: 2))
        }
    }

    private var accessibilityName: String {
        if contact.activity == .needsYou { return String(localized: "\(contact.name), needs you") }
        if contact.unreadCount > 0 { return String(localized: "\(contact.name), \(contact.unreadCount) unread") }
        return contact.name
    }

    private var previewText: String {
        if contact.activity == .working, contact.preview == nil { return String(localized: "Working…") }
        return contact.preview ?? ""
    }
}

/// An agent is waiting on you. A dot, so the preview keeps its room.
struct NeedsYouDot: View {
    var body: some View {
        Circle()
            .fill(Theme.needsYouInk)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Theme.window, lineWidth: 2))
            .accessibilityElement()
            .accessibilityLabel(Text("Needs you"))
    }
}

/// A dot for "needs you", or else the unread count: on a row, and on a folded section for the rows
/// it hides.
struct ContactIndicator: View {
    let needsYou: Bool
    let unreadCount: Int

    var body: some View {
        if needsYou {
            NeedsYouDot()
        } else if unreadCount > 0 {
            Text(unreadCount, format: .number)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.primaryInk)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(Theme.primary))
                .accessibilityLabel(Text("\(unreadCount) unread"))
        }
    }
}
