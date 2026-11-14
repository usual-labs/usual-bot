import HermesKit
import SwiftUI

/// The sidebar: the pinned chats as tiles in the order you put them, then every other agent and
/// room by its newest message, grouped into sections once there are any. A search lists its matches together, then on iPhone the
/// messages that match, and the rail groups without tiles or headings.
struct ContactList: View {
    let contacts: [Contact]
    /// How the list is grouped; `nil` lists everything together.
    var sections: SidebarSections?
    /// Not listed, but still drawn in their rooms' pictures.
    var hiddenBots: [Contact] = []
    /// Shows only contacts whose name or last message contains it.
    var query = ""
    /// The narrow window's rail: avatars only.
    var compact = false
    @Binding var selection: Contact.ID?
    /// Messages that match `query`, shown under the chats (iPhone; the Mac searches in its palette).
    var messages: [MessageHit] = []
    /// Whether the gateway is still searching older messages, or can't be asked.
    var status: MessageSearchStatus = .idle
    var openMessage: (MessageHit) -> Void = { _ in }

    /// The section whose name is being edited in its heading.
    @State private var renaming: ContactSection.ID?
    @State private var deleting: ContactSection?
    /// The block a chat is being dragged over.
    @State private var dropTarget: SidebarBlock.ID?
    @State private var roomEdit: RoomEdit?
    @State private var botEdit: BotEdit?
    #if os(macOS)
        @State private var scrollPosition = ScrollPosition()
    #endif
    @Environment(\.roomEditing) private var roomEditing
    @Environment(\.botEditing) private var botEditing

    var body: some View {
        let byID = Dictionary((contacts + hiddenBots).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let matching = contacts.filter { Self.matches($0, query) }
        Group {
            if matching.isEmpty, messages.isEmpty, status != .searching, !contacts.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text(
                        searchesMessages
                            ? "No chats or messages match “\(term)”" : "No chats match “\(term)”"
                    )
                }
            } else {
                list(blocks(of: matching), byID: byID)
            }
        }
        .roomEditor($roomEdit)
        .botEditor($botEdit)
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible, presenting: deleting
        ) { section in
            Button("Delete", role: .destructive) { sections?.delete(section, contacts: contacts) }
        } message: { _ in
            Text("Its chats move to Other.")
        }
        .alert(
            "Couldn't save that change",
            isPresented: Binding(
                get: { sections?.problem != nil }, set: { if !$0 { sections?.problem = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sections?.problem ?? "")
        }
    }

    static func matches(_ contact: Contact, _ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return contact.name.localizedCaseInsensitiveContains(query)
            || contact.preview?.localizedCaseInsensitiveContains(query) == true
    }

    private var isSearching: Bool {
        !term.isEmpty
    }

    private var term: String { query.trimmingCharacters(in: .whitespaces) }

    private var searchesMessages: Bool {
        #if os(iOS)
            MessageSearch(query) != nil
        #else
            false
        #endif
    }

    /// Whether sections shape the list right now.
    private var isGrouped: Bool {
        sections?.sections.isEmpty == false && !isSearching
    }

    private var showsHeadings: Bool {
        isGrouped && !compact
    }

    private func blocks(of matching: [Contact]) -> [SidebarBlock] {
        let pinOrder = sections?.pinOrder ?? []
        if isSearching {
            return [SidebarBlock(section: nil, contacts: SidebarBlock.ordered(matching, pinOrder: pinOrder))]
        }
        return SidebarBlock.blocks(for: matching, in: sections?.sections ?? [], pinOrder: pinOrder)
    }

    /// Animated, so the chat is seen going to the top or back to its place.
    private func setPinned(_ isPinned: Bool, _ contact: Contact) {
        withAnimation(.smooth(duration: 0.25)) { sections?.setPinned(isPinned, contact) }
    }

    private func pinnedTiles(_ block: SidebarBlock, byID: [Contact.ID: Contact]) -> some View {
        let pinned = block.contacts.map(\.id)
        return PinnedTiles(
            contacts: block.contacts, byID: byID, selection: $selection,
            move: { movePinned($0, to: $1, among: pinned) }
        ) { rowMenu($0, pinned: pinned) }
    }

    private func movePinned(_ id: Contact.ID, to target: Contact.ID, among pinned: [Contact.ID]) {
        withAnimation(.smooth(duration: 0.25)) { sections?.movePinned(id, to: target, among: pinned) }
    }

    /// The rail has no heading to open a folded section with, so it folds nothing.
    private func isFolded(_ block: SidebarBlock) -> Bool {
        showsHeadings && sections?.isFolded(block.id) == true
    }

    private func createSection(moving contact: Contact) {
        guard let section = sections?.create(moving: contact) else { return }
        // Search and the rail show no heading to type the name into.
        if !compact, !isSearching { renaming = section.id }
    }

    private func finishRenaming(_ section: ContactSection, to name: String) {
        if renaming == section.id { renaming = nil }
        sections?.rename(section, to: name, contacts: contacts)
    }

    @ViewBuilder private func list(_ blocks: [SidebarBlock], byID: [Contact.ID: Contact]) -> some View {
        ScrollViewReader { proxy in
            platformList(blocks, byID: byID)
                .onChange(of: renaming) { _, section in
                    if let section { withAnimation { proxy.scrollTo(section) } }
                }
                .onChange(of: selection) { renaming = nil }
        }
    }

    @ViewBuilder private func platformList(_ blocks: [SidebarBlock], byID: [Contact.ID: Contact]) -> some View {
        #if os(macOS)
            // A plain stack instead of `List`, so the selected row gets the light grey pill from the
            // mockups rather than the system accent highlight. Arrow keys move the selection.
            let shown = blocks.flatMap { isFolded($0) ? [] : $0.contacts }
            // Without headings an empty block shows nothing.
            let visible = blocks.filter { showsHeadings || !$0.contacts.isEmpty }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(visible) { block in
                        blockView(block, byID: byID, isFirst: block.id == visible.first?.id)
                    }
                }
                .padding(.horizontal, compact ? 6 : 10)
                .padding(.vertical, 6)
            }
            // The conversation's thin knob, not the system's wide scroller; none in the rail.
            .scrollPosition($scrollPosition)
            .scrollKnob($scrollPosition, hidden: compact)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { moveSelection(by: 1, in: shown) }
            .onKeyPress(.upArrow) { moveSelection(by: -1, in: shown) }
            .background(Theme.window)
        #else
            List(selection: $selection) {
                ForEach(blocks) { block in
                    if block.isPinned {
                        Section {
                            pinnedTiles(block, byID: byID)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .selectionDisabled()
                        }
                    } else {
                        Section {
                            if !isFolded(block) {
                                if showsHeadings, block.contacts.isEmpty { emptyHint(.phone) }
                                ForEach(block.contacts) { contact in
                                    ContactRow(contact: contact, members: Self.members(of: contact, in: byID))
                                        .tag(contact.id)
                                        .contextMenu { rowMenu(contact) }
                                }
                            }
                        } header: {
                            if showsHeadings { heading(block) }
                        }
                    }
                }
                if searchesMessages { messageSection(byID: byID) }
            }
            // Full-width rows, like Messages' list of conversations.
            .listStyle(.plain)
        #endif
    }

    #if os(iOS)
        /// Under the chats: each message that matches, which opens its chat at that message.
        private func messageSection(byID: [Contact.ID: Contact]) -> some View {
            Section {
                if messages.isEmpty, status != .searching {
                    Text("No messages match “\(term)”").foregroundStyle(.secondary)
                }
                ForEach(messages) { hit in
                    if let contact = byID[hit.contactID] {
                        Button {
                            openMessage(hit)
                        } label: {
                            MessageHitRow(
                                hit: hit, contact: contact, members: Self.members(of: contact, in: byID),
                                avatarSize: 44
                            )
                            .padding(.vertical, 4)
                        }
                    }
                }
                if status != .idle { MessageSearchStatusLine(status: status) }
            } header: {
                Text("Messages")
            }
        }
    #endif

    private enum Hint { case mac, phone }

    private func emptyHint(_ hint: Hint) -> some View {
        Group {
            switch hint {
            case .mac: Text("Drag chats here")
            case .phone: Text("Touch and hold a chat to move it here")
            }
        }
        .scaledFont(size: 13)
        .foregroundStyle(Theme.secondaryInk)
        #if os(macOS)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A section's name, or in the middle of renaming it, a field. Other isn't a section, so
    /// it only folds.
    @ViewBuilder private func heading(_ block: SidebarBlock) -> some View {
        if let section = block.section, renaming == section.id {
            SectionNameField(name: section.name) {
                finishRenaming(section, to: $0)
            } cancel: {
                renaming = nil
            }
        } else {
            SectionHeader(
                title: block.section?.name ?? String(localized: "Other"), block: block,
                isFolded: isFolded(block)
            ) {
                withAnimation(.smooth(duration: 0.2)) { sections?.toggleFolded(block.id) }
            } actions: {
                if let section = block.section { sectionMenu(section, block: block) }
            }
        }
    }

    @ViewBuilder private func sectionMenu(_ section: ContactSection, block: SidebarBlock) -> some View {
        let list = sections?.sections ?? []
        Button("Rename") { renaming = section.id }
        Button("Move Up") { sections?.shift(section, by: -1) }
            .disabled(list.first?.id == section.id)
        Button("Move Down") { sections?.shift(section, by: 1) }
            .disabled(list.last?.id == section.id)
        Divider()
        Button("Delete", role: .destructive) {
            // A pinned chat is filed under it too, though it isn't listed there.
            if !contacts.contains(where: { $0.sectionID == section.id }) {
                sections?.delete(section, contacts: contacts)
            } else {
                deleting = section
            }
        }
    }

    /// Pin a chat, and where to file it. A pinned chat shows in no section, so it's filed again
    /// once it's unpinned. A tile moves among the other `pinned` chats; the rail and a search,
    /// which list them as rows, leave that out.
    @ViewBuilder private func rowMenu(_ contact: Contact, pinned: [Contact.ID] = []) -> some View {
        if let sections {
            if contact.isPinned {
                Button("Unpin", systemImage: "pin.slash") { setPinned(false, contact) }
                if pinned.count > 1, let index = pinned.firstIndex(of: contact.id) {
                    Button("Move Left", systemImage: "arrow.left") {
                        movePinned(contact.id, to: pinned[index - 1], among: pinned)
                    }
                    .disabled(index == 0)
                    Button("Move Right", systemImage: "arrow.right") {
                        movePinned(contact.id, to: pinned[index + 1], among: pinned)
                    }
                    .disabled(index == pinned.count - 1)
                }
            } else {
                Button("Pin", systemImage: "pin") { setPinned(true, contact) }
                if sections.sections.isEmpty {
                    Button("Move to New Section", systemImage: "folder.badge.plus") {
                        createSection(moving: contact)
                    }
                } else {
                    Menu("Move to Section", systemImage: "folder") {
                        ForEach(sections.sections.filter { $0.id != contact.sectionID }) { section in
                            Button(section.name) { sections.move(contact, to: section) }
                        }
                        Divider()
                        Button("New Section", systemImage: "folder.badge.plus") { createSection(moving: contact) }
                    }
                    if sections.sections.contains(where: { $0.id == contact.sectionID }) {
                        Button("Remove from Section", systemImage: "folder.badge.minus") {
                            sections.move(contact, to: nil)
                        }
                    }
                }
            }
        }
        if contact.kind == .agent, let botEditing {
            Divider()
            BotMenuItems(contact: contact, editing: botEditing, edit: $botEdit)
        }
        if case .room = contact.kind, roomEditing != nil {
            Divider()
            Button("Rename Room…") { roomEdit = .rename(contact) }
            Button("Delete Room…", role: .destructive) { roomEdit = .delete(contact) }
        }
    }

    #if os(macOS)
        /// A heading and its rows, which together are where a dragged chat lands.
        private func blockView(_ block: SidebarBlock, byID: [Contact.ID: Contact], isFirst: Bool) -> some View {
            // A section takes a chat dragged to it; the pinned chats aren't one.
            let takesDrops = isGrouped && !block.isPinned
            return VStack(spacing: 4) {
                if block.isPinned, !compact {
                    pinnedTiles(block, byID: byID).padding(.bottom, 6)
                } else {
                    if showsHeadings, !block.isPinned {
                        heading(block)
                    } else if compact, !isFirst {
                        Divider().overlay(Theme.border).padding(.vertical, 4)
                    }
                    if !isFolded(block) {
                        if showsHeadings, block.contacts.isEmpty { emptyHint(.mac) }
                        ForEach(block.contacts) { row($0, byID: byID) }
                    }
                }
            }
            .padding(.top, showsHeadings && !isFirst ? 8 : 0)
            .background(
                dropTarget == block.id ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 12)
            )
            .dropDestination(for: SidebarDrag.self) { drags, _ in
                guard takesDrops, let drag = drags.first, let contact = contacts.first(where: { $0.id == drag.id })
                else { return false }
                sections?.move(contact, to: block.section)
                return true
            } isTargeted: { targeted in
                if targeted, takesDrops {
                    dropTarget = block.id
                } else if dropTarget == block.id {
                    dropTarget = nil
                }
            }
        }

        @ViewBuilder private func row(_ contact: Contact, byID: [Contact.ID: Contact]) -> some View {
            let isSelected = contact.id == selection
            let members = Self.members(of: contact, in: byID)
            let row = Button {
                selection = contact.id
            } label: {
                ContactRow(contact: contact, members: members, compact: compact)
                    .padding(.horizontal, compact ? 6 : 10)
                    .padding(.vertical, 4)
                    .background(
                        isSelected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 12)
                    )
                    .hoverHighlight(in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.clickable)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu { rowMenu(contact) }
            // A pinned chat shows in no section, so dragging it to one would show nothing.
            if contact.isPinned {
                row
            } else {
                row.draggable(SidebarDrag(id: contact.id)) {
                    ContactRow(contact: contact, members: members, compact: true)
                }
            }
        }

        private func moveSelection(by offset: Int, in ordered: [Contact]) -> KeyPress.Result {
            guard !ordered.isEmpty else { return .ignored }
            let current = ordered.firstIndex { $0.id == selection }
            let next = current.map { min(max($0 + offset, 0), ordered.count - 1) } ?? 0
            selection = ordered[next].id
            return .handled
        }
    #endif

    static func members(of contact: Contact, in byID: [Contact.ID: Contact]) -> [Contact] {
        guard case .room(let memberIDs) = contact.kind else { return [] }
        return memberIDs.compactMap { byID[$0] }
    }
}
