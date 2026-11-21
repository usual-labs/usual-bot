import HermesKit
import SwiftUI

/// The pinned chats at the top of the sidebar, as in Grok: a large avatar over the name for each,
/// in centred rows, in the order you put them. A tile shows no preview, so its badge says what's
/// waiting. On the Mac a tile dragged onto another takes its place (`SidebarDropRules`).
struct PinnedTiles<Actions: View>: View {
    let contacts: [Contact]
    /// Every contact by ID, to draw a room's members.
    let byID: [Contact.ID: Contact]
    @Binding var selection: Contact.ID?
    #if os(macOS)
        /// The tile a chat is being dragged over.
        var dropTarget: Contact.ID?
        /// Where the tiles are, for the sidebar's drop layer.
        var geometry: SidebarDragGeometry?
    #endif
    /// A tile's context menu.
    @ViewBuilder let actions: (Contact) -> Actions
    #if os(iOS)
        /// The tile last touched, whose menu the row opens.
        @State private var pressed: Contact.ID?
    #endif

    var body: some View {
        let rows = TileRows(minWidth: PinnedTile.minWidth, maxWidth: PinnedTile.maxWidth, spacing: PinnedTile.spacing) {
            ForEach(contacts) { contact in
                tile(contact)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Pinned"))
        #if os(iOS)
            // A List cell opens one context menu, the first it finds, so a menu on each tile gave
            // every tile the first one's and lifted the whole row. The row's one menu is the
            // pressed tile's, and its preview is that tile alone.
            rows.contextMenu {
                if let contact = contacts.first(where: { $0.id == pressed }) { actions(contact) }
            } preview: {
                if let contact = contacts.first(where: { $0.id == pressed }) {
                    let members = ContactList.members(of: contact, in: byID)
                    PinnedTile(contact: contact, members: members, isSelected: false) {}
                        .frame(width: PinnedTile.maxWidth)
                }
            }
        #else
            rows
        #endif
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
        #if os(macOS)
            tile
                .contextMenu { actions(contact) }
                .overlay {
                    SidebarDragSource(id: contact.id) {
                        AgentOrRoomAvatar(contact: contact, members: members, size: 32)
                    }
                }
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(SidebarDragGeometry.space))
                } action: {
                    geometry?.pins[contact.id] = $0
                }
        #else
            tile.gesture(TouchDown { pressed = contact.id })
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

#if os(iOS)
    /// Says when a finger comes down, and fails straight away, so the tile's button still gets
    /// the tap and the list the swipe. A SwiftUI gesture that watched the press kept a swipe that
    /// started on a tile from scrolling the list.
    private struct TouchDown: UIGestureRecognizerRepresentable {
        let action: () -> Void

        func makeUIGestureRecognizer(context: Context) -> Recognizer {
            let recognizer = Recognizer()
            recognizer.cancelsTouchesInView = false
            return recognizer
        }

        func updateUIGestureRecognizer(_ recognizer: Recognizer, context: Context) {
            recognizer.action = action
        }

        final class Recognizer: UIGestureRecognizer {
            var action: () -> Void = {}

            override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
                action()
                state = .failed
            }
        }
    }
#endif

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
