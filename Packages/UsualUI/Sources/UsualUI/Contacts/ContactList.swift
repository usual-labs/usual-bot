import HermesKit
import SwiftUI

/// The sidebar: every agent and room in roster order, grouped into sections once there are any.
/// A search lists its matches together, and the rail groups without headings.
struct ContactList: View {
    let contacts: [Contact]
    /// How the list is grouped; `nil` lists everything together.
    var sections: SidebarSections?
    /// Shows only contacts whose name or last message contains it.
    var query = ""
    /// The narrow window's rail: avatars only.
    var compact = false
    @Binding var selection: Contact.ID?

    /// The section whose name is being edited in its heading.
    @State private var renaming: ContactSection.ID?
    @State private var deleting: ContactSection?
    /// The block a chat is being dragged over.
    @State private var dropTarget: SidebarBlock.ID?

    var body: some View {
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let matching = contacts.filter { Self.matches($0, query) }
        Group {
            if matching.isEmpty, !contacts.isEmpty {
                Text("No chats match “\(query.trimmingCharacters(in: .whitespaces))”")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(blocks(of: matching), byID: byID)
            }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible, presenting: deleting
        ) { section in
            Button("Delete", role: .destructive) { sections?.delete(section, contacts: contacts) }
        } message: { _ in
            Text("Its chats move to Unassigned.")
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
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether sections shape the list right now.
    private var isGrouped: Bool {
        sections?.sections.isEmpty == false && !isSearching
    }

    private var showsHeadings: Bool {
        isGrouped && !compact
    }

    private func blocks(of matching: [Contact]) -> [SidebarBlock] {
        if isGrouped, let sections { return sections.blocks(for: matching) }
        return [SidebarBlock(section: nil, contacts: matching.sorted(by: Contact.rosterOrder))]
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
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(blocks) { block in
                        if showsHeadings || !block.contacts.isEmpty {
                            blockView(block, byID: byID, isFirst: block.id == blocks.first?.id)
                        }
                    }
                }
                .padding(.horizontal, compact ? 6 : 10)
                .padding(.vertical, 6)
            }
            .scrollIndicators(compact ? .hidden : .automatic)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { moveSelection(by: 1, in: shown) }
            .onKeyPress(.upArrow) { moveSelection(by: -1, in: shown) }
            .background(Theme.window)
        #else
            List(selection: $selection) {
                ForEach(blocks) { block in
                    Section {
                        if !isFolded(block) {
                            if showsHeadings, block.contacts.isEmpty { emptyHint(.phone) }
                            ForEach(block.contacts) { contact in
                                ContactRow(contact: contact, members: Self.members(of: contact, in: byID))
                                    .tag(contact.id)
                                    // No line between the bar and the first chat.
                                    .listRowSeparator(
                                        contact.id == block.contacts.first?.id ? .hidden : .automatic, edges: .top
                                    )
                                    .listRowBackground(Color.clear)
                                    .contextMenu { rowMenu(contact) }
                            }
                        }
                    } header: {
                        if showsHeadings {
                            heading(block).listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 2, trailing: 6))
                        }
                    }
                    .listSectionSeparator(.hidden)
                    .listSectionSpacing(6)
                }
            }
            // Full-width rows on the chat colour, like a messenger's chat list.
            .listStyle(.plain)
            .environment(\.defaultMinListHeaderHeight, 0)
            .scrollContentBackground(.hidden)
            .background(Theme.pane)
        #endif
    }

    private enum Hint { case mac, phone }

    private func emptyHint(_ hint: Hint) -> some View {
        Group {
            switch hint {
            case .mac: Text("Drag chats here")
            case .phone: Text("Touch and hold a chat to move it here")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.secondaryInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
    }

    /// A section's name, or in the middle of renaming it, a field. Unassigned isn't a section, so
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
                title: block.section?.name ?? String(localized: "Unassigned"), block: block,
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
            if block.contacts.isEmpty {
                sections?.delete(section, contacts: contacts)
            } else {
                deleting = section
            }
        }
    }

    /// Where to file a chat.
    @ViewBuilder private func rowMenu(_ contact: Contact) -> some View {
        if let sections {
            if sections.sections.isEmpty {
                Button("Move to New Section") { createSection(moving: contact) }
            } else {
                Menu("Move to Section") {
                    ForEach(sections.sections.filter { $0.id != contact.sectionID }) { section in
                        Button(section.name) { sections.move(contact, to: section) }
                    }
                    Divider()
                    Button("New Section") { createSection(moving: contact) }
                }
                if sections.sections.contains(where: { $0.id == contact.sectionID }) {
                    Button("Remove from Section") { sections.move(contact, to: nil) }
                }
            }
        }
    }

    #if os(macOS)
        /// A heading and its rows, which together are where a dragged chat lands.
        private func blockView(_ block: SidebarBlock, byID: [Contact.ID: Contact], isFirst: Bool) -> some View {
            VStack(spacing: 4) {
                if showsHeadings {
                    heading(block)
                } else if isGrouped, !isFirst {
                    Divider().overlay(Theme.border).padding(.vertical, 4)
                }
                if !isFolded(block) {
                    if showsHeadings, block.contacts.isEmpty { emptyHint(.mac) }
                    ForEach(block.contacts) { row($0, byID: byID) }
                }
            }
            .padding(.top, showsHeadings && !isFirst ? 8 : 0)
            .background(
                dropTarget == block.id ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 12)
            )
            .dropDestination(for: SidebarDrag.self) { drags, _ in
                guard isGrouped, let drag = drags.first, let contact = contacts.first(where: { $0.id == drag.id })
                else { return false }
                sections?.move(contact, to: block.section)
                return true
            } isTargeted: { targeted in
                if targeted, isGrouped {
                    dropTarget = block.id
                } else if dropTarget == block.id {
                    dropTarget = nil
                }
            }
        }

        private func row(_ contact: Contact, byID: [Contact.ID: Contact]) -> some View {
            let isSelected = contact.id == selection
            let members = Self.members(of: contact, in: byID)
            return Button {
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
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu { rowMenu(contact) }
            .draggable(SidebarDrag(id: contact.id)) {
                ContactRow(contact: contact, members: members, compact: true)
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
