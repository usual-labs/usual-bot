import HermesKit
import SwiftUI

/// The pinned chats at the top of the sidebar, as in Grok: a large avatar over the name for each,
/// in centred rows, in the order you put them. A tile shows no preview, so its badge says what's
/// waiting. On the Mac a tile dragged onto another takes its place.
struct PinnedTiles<Actions: View>: View {
    let contacts: [Contact]
    /// Every contact by ID, to draw a room's members.
    let byID: [Contact.ID: Contact]
    @Binding var selection: Contact.ID?
    /// Moves the first chat to where the second is.
    var move: (Contact.ID, Contact.ID) -> Void = { _, _ in }
    /// A tile's context menu.
    @ViewBuilder let actions: (Contact) -> Actions
    #if os(macOS)
        /// The tile a pinned chat is being dragged over.
        @State private var dropTarget: Contact.ID?
    #endif

    var body: some View {
        TileRows(minWidth: PinnedTile.minWidth, maxWidth: PinnedTile.maxWidth, spacing: PinnedTile.spacing) {
            ForEach(contacts) { contact in
                tile(contact)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Pinned"))
    }

    @ViewBuilder private func tile(_ contact: Contact) -> some View {
        let members = ContactList.members(of: contact, in: byID)
        #if os(macOS)
            let isTarget = dropTarget == contact.id
        #else
            let isTarget = false
        #endif
        let tile = PinnedTile(
            contact: contact, members: members, isSelected: contact.id == selection || isTarget
        ) {
            selection = contact.id
        }
        .contextMenu { actions(contact) }
        #if os(macOS)
            tile
                .draggable(PinnedDrag(id: contact.id)) {
                    AgentOrRoomAvatar(contact: contact, members: members, size: 32)
                }
                .dropDestination(for: PinnedDrag.self) { drags, _ in
                    guard let drag = drags.first, drag.id != contact.id else { return false }
                    move(drag.id, contact.id)
                    return true
                } isTargeted: { targeted in
                    if targeted {
                        dropTarget = contact.id
                    } else if dropTarget == contact.id {
                        dropTarget = nil
                    }
                }
        #else
            tile
        #endif
    }
}

/// A Bot's or a room's picture.
private struct AgentOrRoomAvatar: View {
    let contact: Contact
    let members: [Contact]
    let size: CGFloat

    var body: some View {
        switch contact.kind {
        case .agent: AgentAvatar(contact: contact, size: size)
        case .room: RoomAvatar(members: members, size: size)
        }
    }
}

private struct PinnedTile: View {
    let contact: Contact
    let members: [Contact]
    let isSelected: Bool
    let open: () -> Void
    @Environment(\.chatShortcuts) private var shortcuts

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let number = shortcuts[contact.id]
        Button(action: open) {
            VStack(spacing: Self.gap) {
                avatar.overlay(alignment: .topTrailing) {
                    // On the circle's edge, which is this far in from the avatar's corner. The
                    // number takes its place while ⌘ is held.
                    let inward = Self.avatarSize * 0.146 - 9
                    if number == nil { AvatarBadge(contact: contact).offset(x: -inward, y: inward) }
                }
                Text(contact.name)
                    .scaledFont(size: Self.nameSize)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1, accessibility: 2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if let number { ShortcutHint(number: number).padding(.top, 4).padding(.trailing, 6) }
            }
            #if os(macOS)
                // The phone pushes the chat, so nothing there stays selected.
                .background(isSelected ? Theme.selection : .clear, in: shape)
                .hoverHighlight(in: shape)
            #endif
            .contentShape(shape)
            #if os(iOS)
                .contentShape(.contextMenuPreview, shape)
            #endif
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: SidebarSpeech.row(contact, preview: "", stamp: nil)))
        }
        .buttonStyle(.clickable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(contact.name)
    }

    private var avatar: some View {
        AgentOrRoomAvatar(contact: contact, members: members, size: Self.avatarSize)
    }

    // Grok's sizes: the phone's tiles are much the larger.
    #if os(iOS)
        static let avatarSize: CGFloat = 88
        static let nameSize: CGFloat = 16
        static let gap: CGFloat = 8
        static let minWidth: CGFloat = 104
        static let maxWidth: CGFloat = 140
        static let spacing: CGFloat = 8
    #else
        static let avatarSize: CGFloat = 56
        static let nameSize: CGFloat = 12
        static let gap: CGFloat = 6
        static let minWidth: CGFloat = 76
        static let maxWidth: CGFloat = 94
        static let spacing: CGFloat = 4
    #endif
}

/// Equal tiles in rows, each row centred. A row takes as many as fit at `minWidth`, and its tiles
/// then widen to share it, up to `maxWidth`.
struct TileRows: Layout {
    var minWidth: CGFloat
    var maxWidth: CGFloat
    var spacing: CGFloat

    /// How many tiles a row of `width` takes, out of `count`, and how wide each is.
    static func fit(
        _ count: Int, in width: CGFloat, minWidth: CGFloat, maxWidth: CGFloat, spacing: CGFloat
    ) -> (perRow: Int, tileWidth: CGFloat) {
        let fits = Int((width + spacing) / (minWidth + spacing))
        let perRow = max(1, min(count, fits))
        let shared = (width - CGFloat(perRow - 1) * spacing) / CGFloat(perRow)
        return (perRow, max(0, min(maxWidth, shared)))
    }

    private func measure(_ subviews: Subviews, in width: CGFloat) -> (perRow: Int, tile: CGSize) {
        let (perRow, tileWidth) = Self.fit(
            subviews.count, in: width, minWidth: minWidth, maxWidth: maxWidth, spacing: spacing)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height }.max()
        return (perRow, CGSize(width: tileWidth, height: height ?? 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        // Asked for its ideal size, one row.
        let ideal = CGFloat(subviews.count) * (maxWidth + spacing) - spacing
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal
        let (perRow, tile) = measure(subviews, in: width)
        let rows = (subviews.count + perRow - 1) / perRow
        return CGSize(width: width, height: CGFloat(rows) * (tile.height + spacing) - spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let (perRow, tile) = measure(subviews, in: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let row = index / perRow
            let inRow = min(perRow, subviews.count - row * perRow)
            let rowWidth = CGFloat(inRow) * (tile.width + spacing) - spacing
            let x = bounds.midX - rowWidth / 2 + CGFloat(index % perRow) * (tile.width + spacing)
            let y = bounds.minY + CGFloat(row) * (tile.height + spacing)
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(tile))
        }
    }
}
