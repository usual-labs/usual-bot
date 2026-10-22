import HermesKit
import SwiftUI

/// The sidebar: every agent and room, in roster order.
struct ContactList: View {
    let contacts: [Contact]
    @Binding var selection: Contact.ID?

    var body: some View {
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = contacts.sorted(by: Contact.rosterOrder)
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
                            ContactRow(contact: contact, members: Self.members(of: contact, in: byID))
                                .padding(.horizontal, 12)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
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
                }
            }
            .listStyle(.sidebar)
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
