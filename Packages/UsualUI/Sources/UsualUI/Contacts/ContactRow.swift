import HermesKit
import SwiftUI

/// One sidebar row: avatar, name, preview and an unread count, with a dot on the avatar when the
/// agent needs you. As in Grok, the phone's list says when each chat was last active and the Mac's
/// sidebar doesn't. Compact, in the narrow window's rail, it's the avatar alone with the count as a
/// badge too.
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
                .accessibilityLabel(Text(verbatim: SidebarSpeech.row(contact, preview: "", stamp: nil)))
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: Self.gap) {
            avatar
                .overlay(alignment: .topTrailing) {
                    if contact.activity == .needsYou { NeedsYouDot().offset(x: 3, y: -2) }
                }
            VStack(alignment: .leading, spacing: Self.lineGap) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(contact.name)
                        .font(Self.nameFont)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    #if os(iOS)
                        Spacer(minLength: 0)
                        if let lastActive = contact.lastActive {
                            Text(Self.stamp(for: lastActive))
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.secondaryInk.opacity(0.75))
                        }
                    #endif
                }
                HStack(spacing: 8) {
                    Text(previewText)
                        .font(Self.previewFont)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ContactIndicator(needsYou: false, unreadCount: contact.unreadCount)
                }
                // The text's own height: the taller unread badge overhangs it rather than moving
                // the row when a count appears.
                .frame(height: Self.previewLineHeight)
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
        private static let nameFont = Font.system(size: 17)
        private static let previewFont = Font.system(size: 15.5)
        private static let previewLineHeight: CGFloat = 19
    #else
        private static let gap: CGFloat = 12
        private static let lineGap: CGFloat = 2
        private static let nameFont = Font.system(size: 15, weight: .medium)
        private static let previewFont = Font.system(size: 13)
        private static let previewLineHeight: CGFloat = 16
    #endif

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
