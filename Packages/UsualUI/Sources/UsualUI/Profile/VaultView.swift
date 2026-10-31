import HermesKit
import SwiftUI

/// What the agent can sign in with: saved items as metadata, and the password managers on the
/// gateway's machine. Secrets go in here but never come back out.
struct VaultView: View {
    let list: VaultList
    let agentName: String
    let isOnline: Bool

    @State private var isAdding = false
    @State private var unlocking: VaultSource?
    @State private var removing: VaultItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch list.phase {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 20)
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await list.refresh() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .frame(maxWidth: .infinity)
            case .ready:
                items
                if !list.managers.isEmpty { managers }
                if let problem = list.problem {
                    Text(problem)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.danger)
                        .padding(.top, 10)
                }
            }
            Text("\(agentName) signs in with these without seeing the passwords. They stay on the gateway, encrypted.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(list.profile) \(isOnline)") { await list.refresh() }
        .sheet(isPresented: $isAdding) { VaultAddSheet(list: list) }
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle("Saved")
                Spacer(minLength: 8)
                Button("Add") { isAdding = true }
                    .buttonStyle(CardButtonStyle(primary: false))
            }
            .padding(.bottom, 4)
            if list.items.isEmpty {
                Text("Nothing saved yet.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.vertical, 8)
            }
            ForEach(list.items) { item in
                VaultItemRow(item: item, managers: list.sources) { removing = item }
                Divider().overlay(Theme.border)
            }
        }
    }

    private var managers: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Password managers")
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(list.managers) { source in
                VaultSourceRow(source: source, list: list) { unlocking = source }
                Divider().overlay(Theme.border)
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.secondaryInk)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct VaultItemRow: View {
    let item: VaultItem
    let managers: [VaultSource]
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !details.isEmpty {
                    Text(details)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if item.isRemovable {
                Button(action: remove) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(item.label)"))
            } else {
                Text(manager)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(Theme.selection, in: Capsule())
            }
        }
        .padding(.vertical, 9)
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
                    .font(.system(size: 14))
                    .foregroundStyle(source.installed ? Theme.ink : Theme.secondaryInk)
                    .lineLimit(1)
                Text(status)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryInk)
            }
            Spacer(minLength: 8)
            if source.installed && source.enabled {
                if source.unlocked {
                    Button("Lock") { Task { await list.lock(source) } }
                        .buttonStyle(CardButtonStyle(primary: false))
                } else {
                    Button("Unlock", action: unlock)
                        .buttonStyle(CardButtonStyle(primary: false))
                }
            }
            Toggle(
                isOn: Binding(
                    get: { source.enabled },
                    set: { enabled in Task { await list.setEnabled(enabled, for: source) } })
            ) {
                Text(source.displayName)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.ink)
            .disabled(!source.installed)
        }
        .padding(.vertical, 9)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Unlock \(source.displayName)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("It stays unlocked for a while on the gateway. The master password isn't kept.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            VaultSecureField(title: "Master password", text: $password)
            if list.isUnencrypted { UnencryptedConsent(isAllowed: $allowsUnencrypted) }
            if let problem = list.problem {
                Text(problem)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") {
                    password = ""
                    dismiss()
                }
                .buttonStyle(CardButtonStyle(primary: false))
                Button("Unlock", action: send)
                    .buttonStyle(CardButtonStyle(primary: true))
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.4)
            }
        }
        .padding(20)
        .frame(minWidth: 320, maxWidth: 420)
        .presentationDetents([.medium])
    }

    private var canSend: Bool {
        !password.isEmpty && !isSending && (!list.isUnencrypted || allowsUnencrypted)
    }

    private func send() {
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
