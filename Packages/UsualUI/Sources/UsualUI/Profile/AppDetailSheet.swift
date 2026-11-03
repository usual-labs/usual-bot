import HermesKit
import SwiftUI

/// One app: where it runs, its switch, its tools from a connection test, sign-in when it uses
/// the provider's page, and removing it.
struct AppDetailSheet: View {
    let list: MCPServerList
    let agentName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isRemoving = false
    private let opened: MCPServer

    init(list: MCPServerList, server: MCPServer, agentName: String) {
        self.list = list
        self.opened = server
        self.agentName = agentName
    }

    /// The server as the list has it now, so the switch and status stay current.
    private var server: MCPServer { list.servers.first { $0.id == opened.id } ?? opened }

    var body: some View {
        SheetForm(title: Text(server.name), action: SheetAction(title: "Done") { dismiss() }) {
            #if os(macOS)
                if !server.isFromPlugin { removeButton }
            #endif
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !server.isFromPlugin { onOff }
                    if server.usesSignIn && !server.isFromPlugin { signIn }
                    tools
                    if !server.envNames.isEmpty {
                        Text("Keys saved on the gateway: \(server.envNames.joined(separator: ", "))")
                            .scaledFont(size: 12.5)
                            .foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let problem = list.problem {
                        Text(problem)
                            .scaledFont(size: 12.5)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    #if os(iOS)
                        if !server.isFromPlugin { removeButton }
                    #endif
                }
                .padding(20)
            }
        }
        .frame(minWidth: 340, idealWidth: 420, maxWidth: 480, minHeight: 420)
        .background(Theme.window)
        .task {
            // Show its tools straight away, unless it's off or already tested.
            if server.enabled, list.checks[server.id] == nil { await list.test(server) }
        }
        .confirmationDialog(
            "Remove “\(server.name)”?", isPresented: $isRemoving, titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { if await list.remove(server) { dismiss() } }
            }
        } message: {
            Text("\(agentName) loses its tools. A key or sign-in saved for it stays on the gateway.")
        }
    }

    /// Red: the label's own colour, as the button style sets the ink for anything without one.
    private var removeButton: some View {
        Button(role: .destructive) {
            isRemoving = true
        } label: {
            Text("Remove").foregroundStyle(Theme.danger)
        }
        .buttonStyle(CardButtonStyle(primary: false))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: AppSymbol.name(for: server))
                .font(.system(size: 18))
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 36, height: 36)
                .background(Theme.selection, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(server.url ?? ([server.command ?? ""] + server.args).joined(separator: " "))
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.secondaryInk)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let plugin = server.plugin {
                    Text("Comes with the \(plugin) plugin, so it can't be changed or removed here.")
                        .scaledFont(size: 12.5)
                        .foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var onOff: some View {
        Toggle(
            isOn: Binding(
                get: { server.enabled },
                set: { enabled in Task { await list.setEnabled(enabled, for: server) } })
        ) {
            Text("Available to \(agentName)")
                .scaledFont(size: 14)
                .foregroundStyle(Theme.ink)
        }
        .toggleStyle(.switch)
        .tint(Theme.switchOn)
    }

    @ViewBuilder private var signIn: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Sign-in")
            switch list.signIns[server.id] {
            case .starting:
                Label {
                    Text("Starting…")
                } icon: {
                    ProgressView().controlSize(.mini)
                }
                .scaledFont(size: 13)
                .foregroundStyle(Theme.secondaryInk)
            case .waiting:
                Text(
                    "Finish signing in on the page that opened in your browser, then come back here. This updates on its own."
                )
                .scaledFont(size: 13)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                Button("Cancel Sign-In") { Task { await list.cancelSignIn(server) } }
                    .buttonStyle(CardButtonStyle(primary: false))
            case .failed(let message):
                Text(message)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                signInButton("Try Again")
            case nil:
                if case .passed = list.checks[server.id] {
                    Text("Signed in. The gateway keeps the sign-in, not this device.")
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    signInButton("Sign In Again", primary: false)
                } else {
                    Text(
                        "\(server.name) asks you to sign in with its provider. The gateway keeps the sign-in, not this device."
                    )
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    signInButton("Sign In")
                }
            }
        }
    }

    private func signInButton(_ title: LocalizedStringKey, primary: Bool = true) -> some View {
        Button(title) {
            let server = server
            Task { await list.signIn(server) { openURL($0) } }
        }
        .buttonStyle(CardButtonStyle(primary: primary))
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Tools")
                Spacer(minLength: 8)
                Button("Test Connection") { Task { await list.test(server) } }
                    .buttonStyle(CardButtonStyle(primary: false))
                    .disabled(list.checks[server.id] == .running)
            }
            switch list.checks[server.id] {
            case .running:
                Label {
                    Text("Connecting from the gateway…")
                } icon: {
                    ProgressView().controlSize(.mini)
                }
                .scaledFont(size: 13)
                .foregroundStyle(Theme.secondaryInk)
            case .passed(let tools) where tools.isEmpty:
                Text("It connected, but offers no tools.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryInk)
            case .passed(let tools):
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tools) { tool in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                                .scaledFont(size: 13.5, design: .monospaced)
                                .foregroundStyle(Theme.ink)
                            if let description = tool.description, !description.isEmpty {
                                Text(description)
                                    .scaledFont(size: 12.5)
                                    .foregroundStyle(Theme.secondaryInk)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                        Divider().overlay(Theme.border)
                    }
                }
            case .failed(let message):
                Text(message)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            case nil:
                Text(
                    server.enabled
                        ? "Test the connection to see its tools." : "It's off. Test the connection to see its tools."
                )
                .scaledFont(size: 13)
                .foregroundStyle(Theme.secondaryInk)
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .scaledFont(size: 12, weight: .semibold)
            .foregroundStyle(Theme.secondaryInk)
            .accessibilityAddTraits(.isHeader)
    }
}
