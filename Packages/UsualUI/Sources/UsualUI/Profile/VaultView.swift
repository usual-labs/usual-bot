import HermesKit
import SwiftUI

/// What the agent can sign in with: saved items as metadata, and the password managers on the
/// gateway's machine. Secrets go in here but never come back out.
struct VaultView: View {
    let list: VaultList
    let agentName: String
    let isOnline: Bool
    /// The Mac panel's Bot and tabs, above the page.
    var top: AnyView? = nil

    /// What New Item is adding.
    @State private var adding: VaultDraft.Kind?
    @State private var filter: Filter = .all
    @State private var unlocking: VaultSource?
    @State private var removing: VaultItem?

    var body: some View {
        ProfileForm(top: top) {
            switch list.phase {
            case .loading:
                Section { ProfileLoading() }
            case .failed(let message):
                Section { ProfileFailure(message: message) { await list.refresh() } }
            case .ready:
                items
                if !list.managers.isEmpty { managers }
            }
        }
        .task(id: "\(list.profile) \(isOnline)") { await list.refresh() }
        .sheet(item: $adding) { VaultAddSheet(list: list, kind: $0) }
        .sheet(item: $unlocking) { VaultUnlockSheet(list: list, source: $0) }
        .confirmationDialog(
            "Remove “\(removing?.label ?? "")”?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible, presenting: removing
        ) { item in
            Button("Remove", role: .destructive) { Task { await list.remove(item) } }
        } message: { _ in
            Text("\(agentName) won't be able to use it any more. This can't be undone.")
        }
    }

    private var items: some View {
        Section {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { option in
                    Text("\(Text(option.title)) (\(list.items.filter(option.includes).count))").tag(option)
                }
            }
            let shown = list.items.filter(filter.includes)
            if shown.isEmpty {
                Text(filter.emptyText).foregroundStyle(.secondary)
            }
            ForEach(shown) { item in
                VaultItemRow(item: item, managers: list.sources) { removing = item }
            }
            if let problem = list.problem {
                Text(problem).foregroundStyle(Theme.danger)
            }
        } header: {
            ProfileSectionHeader("Saved") { newItemMenu }
        } footer: {
            if list.managers.isEmpty { footnote }
        }
    }

    private var newItemMenu: some View {
        Menu {
            Button("Login", systemImage: "key") { adding = .login }
            Button("Card", systemImage: "creditcard") { adding = .payment }
            Button("Address", systemImage: "mappin.and.ellipse") { adding = .address }
        } label: {
            Label("New Item", systemImage: "plus")
        }
    }

    private var managers: some View {
        Section {
            ForEach(list.managers) { source in
                VaultSourceRow(source: source, list: list) { unlocking = source }
            }
        } header: {
            Text("Password managers")
        } footer: {
            footnote
        }
    }

    private var footnote: some View {
        Text("\(agentName) signs in with these without seeing the passwords. They stay on the gateway, encrypted.")
    }
}

/// Which of the saved items show.
private enum Filter: CaseIterable {
    case all, logins, cards, addresses

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .logins: "Logins"
        case .cards: "Cards"
        case .addresses: "Addresses"
        }
    }

    var emptyText: LocalizedStringKey {
        switch self {
        case .all: "Nothing saved yet. Add something with New Item."
        case .logins: "No logins yet. Add one with New Item."
        case .cards: "No cards yet. Add one with New Item."
        case .addresses: "No addresses yet. Add one with New Item."
        }
    }

    func includes(_ item: VaultItem) -> Bool {
        switch self {
        case .all: true
        case .cards: item.kind == "payment"
        case .addresses: item.kind == "address"
        // As the row's icon does, anything else counts as a login.
        case .logins: item.kind != "payment" && item.kind != "address"
        }
    }
}

extension VaultDraft.Kind: @retroactive Identifiable {
    public var id: Self { self }
}

private struct VaultItemRow: View {
    let item: VaultItem
    let managers: [VaultSource]
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .lineLimit(1, accessibility: 3)
                if !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if item.isRemovable {
                Button("Remove \(item.label)", systemImage: "trash", role: .destructive, action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            } else {
                Text(manager)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch item.kind {
        case "payment": "creditcard"
        case "address": "mappin.and.ellipse"
        default: "key"
        }
    }

    /// The manager's name when the gateway reports it.
    private var manager: String {
        managers.first { $0.name == item.backend }?.displayName ?? item.backend
    }

    /// Who you sign in as and where, or failing that when it was saved.
    private var details: String {
        var parts = [item.identifier, item.origin?.replacing(/^https?:\/\//, with: "")].compactMap { $0 }
        if item.hasOtp == true { parts.append(String(localized: "2FA codes")) }
        if parts.isEmpty, let added = item.added {
            parts.append(String(localized: "Added \(added.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct VaultSourceRow: View {
    let source: VaultSource
    let list: VaultList
    let unlock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .foregroundStyle(source.installed ? Theme.ink : Theme.secondaryInk)
                    .lineLimit(1, accessibility: 3)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if source.installed && source.enabled {
                Group {
                    if source.unlocked {
                        Button("Lock") { Task { await list.lock(source) } }
                    } else {
                        Button("Unlock", action: unlock)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Toggle(
                isOn: Binding(
                    get: { source.enabled },
                    set: { enabled in Task { await list.setEnabled(enabled, for: source) } })
            ) {
                Text(source.displayName)
            }
            .labelsHidden()
            .disabled(!source.installed)
        }
    }

    private var status: String {
        if !source.installed { return String(localized: "Not installed on the gateway") }
        if !source.enabled { return String(localized: "Off") }
        return source.unlocked ? String(localized: "Unlocked") : String(localized: "Locked")
    }
}

/// Asks for a password manager's master password from the Vault tab.
private struct VaultUnlockSheet: View {
    let list: VaultList
    let source: VaultSource

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var allowsUnencrypted = false
    @State private var isSending = false

    var body: some View {
        SheetForm(
            title: Text("Unlock \(source.displayName)"), cancel: cancel,
            action: SheetAction(title: "Unlock", isEnabled: canSend, perform: send),
            busy: isSending ? "Unlocking…" : nil
        ) {
            Form {
                Section {
                    VaultSecureField(title: "Master password", text: $password)
                } footer: {
                    Text("It stays unlocked for a while on the gateway. The master password isn't kept.")
                }
                if list.isUnencrypted {
                    Section { UnencryptedConsent(isAllowed: $allowsUnencrypted) }
                }
                if let problem = list.problem {
                    Section {
                        Text(problem).foregroundStyle(Theme.danger)
                    }
                }
            }
        }
        #if os(macOS)
            .frame(width: 420, height: 300)
        #endif
        .presentationDetents([.medium])
    }

    private func cancel() {
        password = ""
        dismiss()
    }

    private var canSend: Bool {
        !password.isEmpty && !isSending && (!list.isUnencrypted || allowsUnencrypted)
    }

    private func send() {
        guard canSend else { return }
        isSending = true
        Task {
            // A failure leaves the password for another try, unless you cancel.
            if await list.unlock(source, password: password, allowingUnencrypted: allowsUnencrypted) {
                password = ""
                dismiss()
            }
            isSending = false
        }
    }
}
