import HermesKit
import SwiftUI

/// The sidebar: every agent and room, in roster order.
struct ContactList: View {
    let contacts: [Contact]
    /// Shows only contacts whose name or last message contains it.
    var query = ""
    /// The narrow window's rail: avatars only.
    var compact = false
    @Binding var selection: Contact.ID?

    var body: some View {
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = contacts.filter { Self.matches($0, query) }.sorted(by: Contact.rosterOrder)
        if ordered.isEmpty, !contacts.isEmpty {
            Text("No chats match “\(query.trimmingCharacters(in: .whitespaces))”")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list(ordered, byID: byID)
        }
    }

    static func matches(_ contact: Contact, _ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return contact.name.localizedCaseInsensitiveContains(query)
            || contact.preview?.localizedCaseInsensitiveContains(query) == true
    }

    @ViewBuilder private func list(_ ordered: [Contact], byID: [Contact.ID: Contact]) -> some View {
        #if os(macOS)
            // A plain stack instead of `List`, so the selected row gets the light grey pill from the
            // mockups rather than the system accent highlight. Arrow keys move the selection.
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(ordered) { contact in
                        let isSelected = contact.id == selection
                        Button {
                            selection = contact.id
                        } label: {
                            ContactRow(contact: contact, members: Self.members(of: contact, in: byID), compact: compact)
                                .padding(.horizontal, compact ? 6 : 12)
                                .padding(.vertical, 4)
                                .background(
                                    isSelected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 14)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, compact ? 6 : 10)
                .padding(.vertical, 6)
            }
            .scrollIndicators(compact ? .hidden : .automatic)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { moveSelection(by: 1, in: ordered) }
            .onKeyPress(.upArrow) { moveSelection(by: -1, in: ordered) }
            .background(Theme.window)
        #else
            List(selection: $selection) {
                ForEach(ordered) { contact in
                    ContactRow(contact: contact, members: Self.members(of: contact, in: byID))
                        .tag(contact.id)
                        // No line between the bar and the first chat.
                        .listRowSeparator(contact.id == ordered.first?.id ? .hidden : .automatic, edges: .top)
                }
            }
            // Full-width rows on the window colour, like a messenger's chat list.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.window)
        #endif
    }

    #if os(macOS)
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
