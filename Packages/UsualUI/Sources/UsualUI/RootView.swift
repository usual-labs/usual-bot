import HermesKit
import SwiftUI

/// The main window: the connect screen until signed in, then contacts and the selected thread.
public struct RootView: View {
    @Bindable var model: AppModel
    let presenter: any SignInPresenter

    public init(model: AppModel, presenter: any SignInPresenter) {
        self.model = model
        self.presenter = presenter
    }

    public var body: some View {
        switch model.session {
        case .signedOut, .signingIn:
            ConnectView(model: model, presenter: presenter)
        case .signedIn(let gateway):
            ContactsSplitView(contacts: model.contacts, emptyText: emptyText) {
                GatewayStatusButton(gateway: gateway, link: model.link, signOut: model.signOut)
            }
        }
    }

    private var emptyText: LocalizedStringKey {
        if case .online = model.link { return "No agents on this gateway yet." }
        return "Connecting…"
    }
}

/// Contacts on the left, the selected thread on the right. On iPhone the split view collapses
/// into a list that pushes the thread.
struct ContactsSplitView<Footer: View>: View {
    let contacts: [Contact]
    var emptyText: LocalizedStringKey = "No agents yet."
    @ViewBuilder let footer: Footer

    @State private var selection: Contact.ID?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if contacts.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContactList(contacts: contacts, selection: $selection)
                }
                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(Theme.window)
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

/// The sidebar footer: which gateway, whether it's reachable, and sign-out.
struct GatewayStatusButton: View {
    let gateway: GatewayAddress
    let link: AppModel.Link
    let signOut: () -> Void

    var body: some View {
        Menu {
            Section(gateway.displayName) {
                Text(statusText)
            }
            Button("Sign Out", role: .destructive, action: signOut)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Gateway \(gateway.displayName), \(statusText)"))
    }

    private var label: String {
        switch link {
        case .online: return gateway.displayName
        case .connecting: return String(localized: "Connecting…")
        case .offline: return String(localized: "Offline, retrying…")
        }
    }

    private var statusText: String {
        switch link {
        case .online(let dialect):
            return dialect == .canonical ? String(localized: "Connected") : String(localized: "Connected (dashboard)")
        case .connecting: return String(localized: "Connecting…")
        case .offline(let reason): return reason
        }
    }

    private var dotColor: Color {
        switch link {
        case .online: return Theme.online
        case .connecting: return Theme.needsYouInk
        case .offline: return Theme.danger
        }
    }
}

#Preview("Contacts") {
    ContactsSplitView(contacts: SampleData.contacts()) { EmptyView() }
        .frame(width: 1000, height: 640)
}
