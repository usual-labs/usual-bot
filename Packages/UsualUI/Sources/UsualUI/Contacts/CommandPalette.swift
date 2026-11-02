#if os(macOS)
    import HermesKit
    import SwiftUI

    /// Finds a chat or runs an action from the keyboard: ⌘K, or the sidebar's Search.
    struct CommandPalette: View {
        let contacts: [Contact]
        let members: (Contact) -> [Contact]
        let canCreateRoom: Bool
        let open: (Contact.ID) -> Void
        let newRoom: () -> Void
        let settings: () -> Void
        let close: () -> Void

        @AppStorage(AppPreferences.appearanceKey) private var appearance = "system"
        @State private var query = ""
        @State private var highlighted = 0
        @FocusState private var fieldIsFocused: Bool

        private struct Entry: Identifiable {
            enum Look {
                case contact(Contact)
                case icon(String)
            }
            let id: String
            let title: String
            let detail: String
            let look: Look
            let run: () -> Void
        }

        var body: some View {
            ZStack(alignment: .top) {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                card.padding(.top, 88)
            }
            .onAppear { fieldIsFocused = true }
            .onChange(of: query) { highlighted = 0 }
        }

        private var card: some View {
            let entries = entries
            return VStack(spacing: 0) {
                TextField("Search chats and actions", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldIsFocused)
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .onSubmit { run(entries) }
                    .onExitCommand(perform: close)
                    .onKeyPress(.downArrow) { move(1, in: entries) }
                    .onKeyPress(.upArrow) { move(-1, in: entries) }
                Divider()
                if entries.isEmpty {
                    Text("Nothing matches “\(query.trimmingCharacters(in: .whitespaces))”")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    results(entries)
                }
            }
            .frame(width: 574)
            .background(Theme.pane, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
            .accessibilityAddTraits(.isModal)
        }

        private func results(_ entries: [Entry]) -> some View {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                close()
                                entry.run()
                            } label: {
                                row(entry, isHighlighted: index == highlighted)
                            }
                            .buttonStyle(.plain)
                            .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: highlighted) {
                    if entries.indices.contains(highlighted) { scroller.scrollTo(entries[highlighted].id) }
                }
            }
        }

        private func row(_ entry: Entry, isHighlighted: Bool) -> some View {
            HStack(spacing: 12) {
                switch entry.look {
                case .contact(let contact):
                    if case .room = contact.kind {
                        RoomAvatar(members: members(contact), size: 32)
                    } else {
                        AgentAvatar(contact: contact, size: 32)
                    }
                case .icon(let name):
                    Image(systemName: name)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .background(isHighlighted ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        }

        private var entries: [Entry] {
            let recent = contacts.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
            let chats = recent.filter { ContactList.matches($0, query) }.map { contact in
                Entry(
                    id: contact.id, title: contact.name, detail: contact.preview ?? "", look: .contact(contact),
                    run: { open(contact.id) })
            }
            let term = query.trimmingCharacters(in: .whitespaces)
            return chats + actions.filter { term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) }
        }

        private var actions: [Entry] {
            var list: [Entry] = []
            if canCreateRoom {
                list.append(
                    Entry(
                        id: "new-room", title: String(localized: "New Room"), detail: "", look: .icon("plus"),
                        run: newRoom)
                )
            }
            list.append(
                Entry(
                    id: "settings", title: String(localized: "Settings"), detail: "", look: .icon("gearshape"),
                    run: settings))
            list.append(theme("system", String(localized: "Theme: System"), icon: "circle.lefthalf.filled"))
            list.append(theme("light", String(localized: "Theme: Light"), icon: "sun.max"))
            list.append(theme("dark", String(localized: "Theme: Dark"), icon: "moon"))
            return list
        }

        private func theme(_ value: String, _ title: String, icon: String) -> Entry {
            let detail = appearance == value ? String(localized: "Current") : ""
            return Entry(id: "theme-\(value)", title: title, detail: detail, look: .icon(icon)) { appearance = value }
        }

        private func move(_ step: Int, in entries: [Entry]) -> KeyPress.Result {
            guard !entries.isEmpty else { return .ignored }
            highlighted = (highlighted + step + entries.count) % entries.count
            return .handled
        }

        private func run(_ entries: [Entry]) {
            guard entries.indices.contains(highlighted) else { return }
            close()
            entries[highlighted].run()
        }
    }
#endif
