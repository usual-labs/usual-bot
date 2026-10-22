import HermesKit
import SwiftUI

/// The main window: contacts on the left, the selected thread on the right.
/// On iPhone the same split view collapses into a list that pushes the thread.
public struct RootView: View {
    let contacts: [Contact]
    @State private var selection: Contact.ID?

    public init(contacts: [Contact]) {
        self.contacts = contacts
    }

    public var body: some View {
        NavigationSplitView {
            ContactList(contacts: contacts, selection: $selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            if let contact = contacts.first(where: { $0.id == selection }) {
                ThreadPane(contact: contact, members: members(of: contact))
            } else {
                ContentUnavailableView(
                    "No chat selected", systemImage: "bubble.left.and.bubble.right",
                    description: Text("Pick an agent or a room from the list."))
            }
        }
        .tint(Theme.ink)
    }

    private func members(of contact: Contact) -> [Contact] {
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ContactList.members(of: contact, in: byID)
    }
}

#Preview {
    RootView(contacts: SampleData.contacts())
        .frame(width: 1000, height: 640)
}
