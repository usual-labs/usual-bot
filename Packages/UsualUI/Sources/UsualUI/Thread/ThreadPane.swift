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
                    .padding(.top, Self.barMargin)
                    .padding(.bottom, 8)
            } bottom: {
                if let thread, thread.phase == .ready {
                    Composer(thread: thread, agentName: contact.name)
                        .frame(maxWidth: 780)
                        .padding(.horizontal, 20)
                        .padding(.bottom, Self.barMargin)
                        .padding(.top, 8)
                }
            }
            .task(id: contact.id) { open() }
            .paneChrome()
    }

    /// The name's distance from the top, centring it on the line of the window buttons and the
    /// sidebar's buttons on the Mac; the message box keeps the same distance from the bottom.
    static var barMargin: CGFloat {
        #if os(macOS)
            9
        #else
            12
        #endif
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
    /// The chat column's look: the pane colour, filling its column.
    func paneChrome() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.pane)
            #if os(macOS)
                // The window has no title bar, so the name sits as far from the window's top edge
                // as the message box does from its bottom edge.
                .ignoresSafeArea(.container, edges: .top)
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
        HStack(spacing: 8) {
            switch contact.kind {
            case .agent: AgentAvatar(contact: contact, size: 26)
            case .room: RoomAvatar(members: members, size: 26)
            }
            Text(contact.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .padding(.leading, 5)
        .padding(.trailing, 16)
        // As tall as the sidebar's Search and New Room, on the same line as them.
        .frame(height: 36)
        .floatingSurface(in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
