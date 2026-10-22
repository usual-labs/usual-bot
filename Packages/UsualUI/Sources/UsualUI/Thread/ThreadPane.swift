import HermesKit
import SwiftUI

/// The chat column for one contact. On the Mac it is a rounded pane sitting on the grey window.
struct ThreadPane: View {
    let contact: Contact
    let members: [Contact]

    var body: some View {
        VStack(spacing: 0) {
            NamePill(contact: contact, members: members)
                .padding(.top, 12)
            Spacer()
            Text("No messages yet")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pane)
        #if os(macOS)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
            .padding(8)
            .background(Theme.window)
        #endif
    }
}

/// The floating, centred pill at the top of a thread: avatar and name.
struct NamePill: View {
    let contact: Contact
    let members: [Contact]

    var body: some View {
        HStack(spacing: 10) {
            switch contact.kind {
            case .agent: AgentAvatar(contact: contact, size: 32)
            case .room: RoomAvatar(members: members, size: 32)
            }
            Text(contact.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .padding(.leading, 7)
        .padding(.trailing, 20)
        .frame(height: 46)
        .background(Capsule().fill(Theme.pane))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .overlay(Capsule().strokeBorder(.black.opacity(0.04)))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
