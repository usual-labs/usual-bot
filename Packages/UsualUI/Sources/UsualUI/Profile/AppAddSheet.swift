import HermesKit
import SwiftUI

/// Adds an app: one from Hermes's catalog with the keys it asks for, or one you describe. Keys
/// and tokens live only in this sheet and go to the gateway when you add; closing clears them.
struct AppAddSheet: View {
    private enum Source: Hashable { case catalog, custom }

    let list: MCPServerList
    /// Called with a new app's name when it wants signing in next.
    let wantsSignIn: (MCPServer.ID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source = Source.catalog
    @State private var search = ""
    @State private var entry: MCPCatalogEntry?
    @State private var values: [String: String] = [:]
    @State private var draft = MCPServerDraft()
    @State private var isAdding = false
    @State private var allowsUnencrypted = false

    var body: some View {
        SheetForm(
            title: Text("New App"),
            back: source == .catalog && entry != nil
                ? SheetBack(label: Text("Back to the catalog")) { pick(nil) } : nil,
            cancel: close,
            action: source == .custom || entry != nil
                ? SheetAction(title: "Add", isEnabled: canAdd, perform: add) : nil,
            busy: isAdding ? "Adding…" : nil
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Add from", selection: $source) {
                        Text("Catalog").tag(Source.catalog)
                        Text("Custom").tag(Source.custom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch source {
                    case .catalog:
                        if let entry { entryForm(entry) } else { catalog }
                    case .custom: custom
                    }
                    if list.isUnencrypted && sendsSecret { UnencryptedConsent(isAllowed: $allowsUnencrypted) }
                    if let problem = list.problem {
                        Text(problem)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 340, idealWidth: 420, maxWidth: 480, minHeight: 460)
        .background(Theme.window)
        .task {
            list.clearMessages()
            await list.loadCatalog()
        }
    }

    // MARK: - Catalog

    @ViewBuilder private var catalog: some View {
        VaultTextField(title: "Search the catalog", text: $search, isLiteral: true)
        switch list.catalogPhase {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 20)
        case .failed(let message):
            Text("Couldn't load the catalog: \(message)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
        case .ready:
            let shown = list.catalog.filter(matches)
            if shown.isEmpty {
                Text(search.isEmpty ? "The catalog is empty. Use Custom instead." : "Nothing matches. Try Custom.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryInk)
            }
            VStack(spacing: 0) {
                ForEach(shown) { entry in
                    CatalogRow(entry: entry) { pick(entry) }
                    Divider().overlay(Theme.border)
                }
            }
        }
    }

    private func matches(_ entry: MCPCatalogEntry) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || entry.name.localizedCaseInsensitiveContains(query)
            || entry.description.localizedCaseInsensitiveContains(query)
    }

    @ViewBuilder private func entryForm(_ entry: MCPCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(entry.description)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let place = entry.url ?? entry.command {
            Text(entry.url != nil ? "Connects to \(place)" : "Runs \(place) on the gateway's machine")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryInk)
                .textSelection(.enabled)
        }
        ForEach(entry.requiredEnv) { key in
            VStack(alignment: .leading, spacing: 4) {
                VaultSecureField(
                    title: LocalizedStringKey(
                        key.required ? key.prompt ?? key.name : "\(key.prompt ?? key.name) (optional)"),
                    text: Binding(get: { values[key.name] ?? "" }, set: { values[key.name] = $0 }))
                Text(key.name)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityHidden(true)
            }
        }
        if !entry.requiredEnv.isEmpty {
            note("Keys go to the gateway and are saved there. This device doesn't keep them.")
        }
        if entry.usesSignIn { note("After adding it, sign in with its provider in your browser.") }
        if entry.needsInstall { note("The gateway fetches and builds it first, which can take a few minutes.") }
        if entry.installed { note("It's already added. Adding it again replaces its settings.") }
    }

    // MARK: - Custom

    @ViewBuilder private var custom: some View {
        VaultTextField(title: "Name, like docs", text: $draft.name, isLiteral: true)
        Picker("Kind", selection: $draft.kind) {
            Text("Web address").tag(MCPServerDraft.Kind.web)
            Text("Program").tag(MCPServerDraft.Kind.program)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        switch draft.kind {
        case .web:
            VaultTextField(title: "Address, like https://example.com/mcp", text: $draft.url, isLiteral: true)
            Picker("Sign-in", selection: $draft.auth) {
                Text("None").tag(MCPServerDraft.Auth.none)
                Text("Token").tag(MCPServerDraft.Auth.token)
                Text("Provider page").tag(MCPServerDraft.Auth.signIn)
            }
            .pickerStyle(.segmented)
            switch draft.auth {
            case .token:
                VaultSecureField(title: "Token", text: $draft.token)
                note("The token goes to the gateway and is saved there. This device doesn't keep it.")
            case .signIn:
                note("After adding it, sign in with its provider in your browser.")
            case .none:
                EmptyView()
            }
        case .program:
            VaultTextField(title: "Command, like npx", text: $draft.command, isLiteral: true)
            VaultTextField(title: "Arguments, separated by spaces", text: $draft.arguments, isLiteral: true)
            note("The gateway runs this program on its machine, with Hermes's permissions. Add only one you trust.")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Adding

    /// A token or key would go out with this add.
    private var sendsSecret: Bool {
        switch source {
        case .custom: draft.hasSecret
        case .catalog: entry != nil && values.values.contains { !$0.isEmpty }
        }
    }

    private var canAdd: Bool {
        guard !isAdding, !list.isUnencrypted || !sendsSecret || allowsUnencrypted else { return false }
        switch source {
        case .custom:
            return draft.isComplete
        case .catalog:
            guard let entry else { return false }
            return entry.requiredEnv.allSatisfy { !$0.required || !(values[$0.name] ?? "").isEmpty }
        }
    }

    private func pick(_ picked: MCPCatalogEntry?) {
        entry = picked
        values = [:]
        allowsUnencrypted = false
    }

    private func add() {
        guard canAdd else { return }
        isAdding = true
        Task {
            let added: Bool
            var signInNext: MCPServer.ID?
            switch source {
            case .custom:
                added = await list.add(draft, allowingUnencrypted: allowsUnencrypted)
                if draft.kind == .web, draft.auth == .signIn {
                    signInNext = draft.name.trimmingCharacters(in: .whitespaces)
                }
            case .catalog:
                guard let entry else {
                    isAdding = false
                    return
                }
                added = await list.install(entry, values: values, allowingUnencrypted: allowsUnencrypted)
                if entry.usesSignIn { signInNext = entry.name }
            }
            isAdding = false
            // A failure keeps the form to fix and try again, unless you cancel.
            if added {
                if let signInNext { wantsSignIn(signInNext) }
                close()
            }
        }
    }

    private func close() {
        values = [:]
        draft = MCPServerDraft()
        allowsUnencrypted = false
        dismiss()
    }
}

private struct CatalogRow: View {
    let entry: MCPCatalogEntry
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink)
                    Text(entry.description)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(2)
                    if let needs {
                        Text(needs)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: 8)
                if entry.installed {
                    Text("Added")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryInk)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clickable)
        .accessibilityElement(children: .combine)
    }

    /// What it asks of you before it works.
    private var needs: String? {
        if !entry.requiredEnv.isEmpty { return String(localized: "Needs a key") }
        if entry.usesSignIn { return String(localized: "Needs sign-in") }
        return nil
    }
}
