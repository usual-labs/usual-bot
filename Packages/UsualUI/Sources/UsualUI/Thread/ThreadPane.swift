import HermesKit
import SwiftUI

/// The chat column for one contact: the conversation runs the pane's full height, under the
/// name at the top and the message box at the bottom.
struct ThreadPane: View {
    let contact: Contact
    let members: [Contact]
    /// `nil` for contacts without a chat yet (rooms arrive in a later milestone).
    let thread: ChatThread?
    var open: () -> Void = {}
    /// Shows or hides the agent's profile; `nil` when the contact has none.
    var toggleProfile: (() -> Void)? = nil

    var body: some View {
        content
            .chatBars {
                namePill
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            } bottom: {
                if let thread, thread.phase == .ready {
                    Composer(thread: thread, agentName: contact.name)
                        .frame(maxWidth: 780)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .padding(.top, 8)
                }
            }
            .task(id: contact.id) { open() }
            .paneChrome()
    }

    @ViewBuilder private var namePill: some View {
        if let toggleProfile {
            Button(action: toggleProfile) { NamePill(contact: contact, members: members) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows routines and details"))
                .keyboardShortcut("i", modifiers: .command)
        } else {
            NamePill(contact: contact, members: members)
        }
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

extension View {
    /// The chat column's look: on the Mac, a rounded pane sitting on the grey window, its corners
    /// concentric with the window's (16 pt on macOS 26) across the gap between them.
    func paneChrome() -> some View {
        #if os(macOS)
            let gap: CGFloat = 8
            let corners = RoundedRectangle(cornerRadius: 16 - gap)
            return frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.pane)
                .clipShape(corners)
                .overlay(corners.strokeBorder(Theme.border))
                .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
                .padding(gap)
                .background(Theme.window)
                // The window has no title bar, so the pane sits as far from the window's top
                // edge as from its other edges.
                .ignoresSafeArea(.container, edges: .top)
        #else
            return frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.pane)
        #endif
    }

    /// Pins `top` and `bottom` over a conversation that scrolls beneath them.
    func chatBars(@ViewBuilder top: () -> some View, @ViewBuilder bottom: () -> some View) -> some View {
        safeAreaInset(edge: .top, spacing: 0, content: top)
            .safeAreaInset(edge: .bottom, spacing: 0, content: bottom)
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
        .floatingSurface(in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
