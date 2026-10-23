import HermesKit
import SwiftUI

/// One sidebar row: avatar, name, time of last activity, preview and an indicator. Compact, in the
/// narrow window's rail, it is the avatar alone with the indicator as a badge.
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(contact.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let lastActive = contact.lastActive {
                        Text(Self.stamp(for: lastActive))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                HStack(spacing: 8) {
                    Text(previewText)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    indicator
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var avatar: some View {
        switch contact.kind {
        case .agent: AgentAvatar(contact: contact)
        case .room: RoomAvatar(members: members)
        }
    }

    /// The rail's corner badge: the unread count, or a dot when the agent needs you.
    @ViewBuilder private var badge: some View {
        if contact.activity == .needsYou {
            Circle()
                .fill(Theme.needsYouInk)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Theme.window, lineWidth: 2))
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

    @ViewBuilder private var indicator: some View {
        if contact.activity == .needsYou {
            Text("Needs you")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.needsYouInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.needsYouFill))
        } else if contact.unreadCount > 0 {
            Text(contact.unreadCount, format: .number)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.primaryInk)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(Theme.primary))
                .accessibilityLabel(Text("\(contact.unreadCount) unread"))
        }
    }

    /// "10:44" today, the weekday within the last week, otherwise the date.
    static func stamp(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
