import HermesKit
import SwiftUI

/// One sidebar row: avatar, name, preview and an unread count, with a dot on the avatar when the
/// agent needs you. As in Grok, the phone's list says when each chat was last active and the Mac's
/// sidebar doesn't. Compact, in the narrow window's rail, it's the avatar alone with the count as a
/// badge too. A pinned chat is a row only in a search and the rail (`PinnedTiles` otherwise), and
/// a search marks it with a pin.
struct ContactRow: View {
    let contact: Contact
    /// Resolved members when `contact` is a room; empty for agents.
    let members: [Contact]
    var compact = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scaledAvatar: CGFloat = 44

    var body: some View {
        if compact {
            avatar
                .overlay(alignment: .topTrailing) { AvatarBadge(contact: contact).offset(x: 6, y: -4) }
                .padding(.vertical, 4)
                .help(contact.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: SidebarSpeech.row(contact, preview: "", stamp: nil)))
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: Self.gap) {
            avatar
                .overlay(alignment: .topTrailing) {
                    if contact.activity == .needsYou { NeedsYouDot().offset(x: 3, y: -2) }
                }
            VStack(alignment: .leading, spacing: Self.lineGap) {
                // At accessibility text sizes the time moves under the name, so neither is cut short.
                let nameLine =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Self.lineGap))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                nameLine {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(contact.name)
                            .scaledFont(size: Self.nameSize, weight: Self.nameWeight)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1, accessibility: 2)
                        if contact.isPinned {
                            Image(systemName: "pin.fill")
                                .scaledFont(size: Self.previewSize - 3)
                                .foregroundStyle(Theme.secondaryInk.opacity(0.75))
                        }
                    }
                    #if os(iOS)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        if let lastActive = contact.lastActive {
                            Text(Self.stamp(for: lastActive))
                                .scaledFont(size: 14)
                                .foregroundStyle(Theme.secondaryInk.opacity(0.75))
                        }
                    #endif
                }
                HStack(spacing: 8) {
                    Text(previewText)
                        .scaledFont(size: Self.previewSize)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1, accessibility: 3)
                    Spacer(minLength: 0)
                    ContactIndicator(needsYou: false, unreadCount: contact.unreadCount)
                }
                // The text's own height: the taller unread badge overhangs it rather than moving
                // the row when a count appears. At accessibility sizes the preview wraps instead.
                .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : previewLineHeight)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: SidebarSpeech.row(contact, preview: previewText, stamp: spokenStamp)))
    }

    /// The phone's list says when each chat was last active; the Mac's sidebar doesn't.
    private var spokenStamp: String? {
        #if os(iOS)
            contact.lastActive.map { Self.stamp(for: $0) }
        #else
            nil
        #endif
    }

    // Grok's phone list is roomier than the Mac's sidebar: larger type, more space around the avatar.
    #if os(iOS)
        private static let gap: CGFloat = 16
        private static let lineGap: CGFloat = 4
        private static let nameSize: CGFloat = 17
        private static let nameWeight: Font.Weight? = nil
        private static let previewSize: CGFloat = 15.5
        private static let previewLineHeight: CGFloat = 19
    #else
        private static let gap: CGFloat = 12
        private static let lineGap: CGFloat = 2
        private static let nameSize: CGFloat = 15
        private static let nameWeight: Font.Weight? = .medium
        private static let previewSize: CGFloat = 13
        private static let previewLineHeight: CGFloat = 16
    #endif

    /// One line of preview, grown in step with its text.
    private var previewLineHeight: CGFloat {
        Self.previewLineHeight * Theme.scaled(Self.previewSize, for: dynamicTypeSize) / Self.previewSize
    }

    @ViewBuilder private var avatar: some View {
        switch contact.kind {
        case .agent: AgentAvatar(contact: contact, size: avatarSize)
        case .room: RoomAvatar(members: members, size: avatarSize)
        }
    }

    /// iPhone rows and the Mac's rail keep the larger avatar; the Mac's rows have the name to go by.
    /// On iPhone it grows with the text, but only so far: the name needs the room more.
    private var avatarSize: CGFloat {
        #if os(macOS)
            compact ? 44 : 36
        #else
            min(scaledAvatar, 60)
        #endif
    }

    private var previewText: String {
        if contact.activity == .working, contact.preview == nil { return String(localized: "Working…") }
        return contact.preview ?? ""
    }
}

/// The badge on an avatar that stands alone, in the rail and on a pinned chat: the unread count, or
/// a dot when the agent needs you.
struct AvatarBadge: View {
    let contact: Contact

    var body: some View {
        if contact.activity == .needsYou {
            NeedsYouDot()
        } else if contact.unreadCount > 0 {
            Text(contact.unreadCount, format: .number)
                .scaledFont(size: 10.5, weight: .semibold)
                .foregroundStyle(Theme.primaryInk)
                .padding(.horizontal, 4)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(Theme.primary))
                .overlay(Capsule().strokeBorder(Theme.window, lineWidth: 2))
        }
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
                .scaledFont(size: 11.5, weight: .semibold)
                .foregroundStyle(Theme.primaryInk)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(Theme.primary))
                .accessibilityLabel(Text("\(unreadCount) unread"))
        }
    }
}

extension ContactRow {
    /// "10:44 AM" today, "Yesterday", the weekday within the week, otherwise the date.
    nonisolated static func stamp(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return String(localized: "Yesterday")
        }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day
        if let days, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
