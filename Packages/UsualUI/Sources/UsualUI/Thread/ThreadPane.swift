import HermesKit
import SwiftUI

/// The chat column for one contact. On the Mac it is a rounded pane sitting on the grey window.
struct ThreadPane: View {
    let contact: Contact
    let members: [Contact]
    /// `nil` for contacts without a chat yet (rooms arrive in a later milestone).
    let thread: ChatThread?
    var open: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            NamePill(contact: contact, members: members)
                .padding(.top, 12)
                .padding(.bottom, 4)
            content
            if let thread, thread.phase == .ready {
                Composer(thread: thread, agentName: contact.name)
                    .frame(maxWidth: 780)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: contact.id) { open() }
        .background(Theme.pane)
        #if os(macOS)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
            .padding(8)
            .background(Theme.window)
        #endif
    }

    @ViewBuilder private var content: some View {
        switch thread?.phase {
        case nil:
            centred { Text("No messages yet") }
        case .loading:
            centred { ProgressView().controlSize(.small) }
        case .failed(let message):
            centred {
                VStack(spacing: 10) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Try Again", action: open)
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 32)
            }
        case .ready:
            if let thread {
                TranscriptView(thread: thread, agentName: contact.name)
            }
        }
    }

    private func centred(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.system(size: 13))
            .foregroundStyle(Theme.secondaryInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
