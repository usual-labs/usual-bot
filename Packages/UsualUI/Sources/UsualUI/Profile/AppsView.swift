import HermesKit
import SwiftUI

/// The agent's apps: the MCP servers its profile uses, each with a switch. Opening one shows its
/// tools; New App brings one in from Hermes's catalog or by address.
struct AppsView: View {
    let list: MCPServerList
    var connectors: ConnectorList? = nil
    let agentName: String
    /// The Mac panel's Bot and tabs, above the page.
    var top: AnyView? = nil

    @State private var selected: MCPServer?
    @State private var isAdding = false
    /// A server just added that wants signing in, opened once the add sheet has gone.
    @State private var openAfterAdding: MCPServer.ID?

    var body: some View {
        ProfileForm(top: top) {
            Section {
                switch list.phase {
                case .loading:
                    ProfileLoading()
                case .failed(let message):
                    ProfileFailure(message: message) { await list.refresh() }
                case .ready:
                    servers
                }
            } header: {
                ProfileSectionHeader("Connected") {
                    Button("New App", systemImage: "plus") { isAdding = true }
                        .disabled(list.phase != .ready)
                }
            } footer: {
                Text(
                    "Apps connect \(agentName) to other services through MCP servers on your gateway. Hermes runs them, and \(agentName) uses their tools in chat."
                )
            }
            if let connectors { ConnectorsSection(list: connectors, agentName: agentName) }
        }
        .task(id: list.profile) {
            // The connected accounts' section can be empty, with nothing to hang its own load on.
            async let servers: Void = list.refresh()
            async let accounts: Void? = connectors?.refresh()
            _ = await (servers, accounts)
        }
        .sheet(item: $selected) { AppDetailSheet(list: list, server: $0, agentName: agentName) }
        .sheet(isPresented: $isAdding, onDismiss: openAddedServer) {
            AppAddSheet(list: list) { openAfterAdding = $0 }
        }
    }

    @ViewBuilder private var servers: some View {
        if list.needsApply { ApplyNote(list: list, agentName: agentName) }
        if list.servers.isEmpty {
            Text("No apps yet. Add one to give \(agentName) more tools.").foregroundStyle(.secondary)
        }
        ForEach(list.servers) { server in
            AppRow(server: server, list: list) { selected = server }
        }
        if let notice = list.notice {
            Text(notice).foregroundStyle(.secondary)
        }
        if let problem = list.problem {
            Text(problem).foregroundStyle(Theme.danger)
        }
    }

    private func openAddedServer() {
        guard let name = openAfterAdding else { return }
        openAfterAdding = nil
        selected = list.servers.first { $0.id == name }
    }
}

/// Says a change hasn't reached running chats yet, and offers to apply it to the open one.
private struct ApplyNote: View {
    let list: MCPServerList
    let agentName: String

    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved on the gateway. \(agentName) gets the change in its next session.")
            if list.canApplyNow {
                Text(
                    "To use it in the open chat now, apply it. \(agentName)'s next reply costs more, since the whole conversation is sent again."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Button {
                    isApplying = true
                    Task {
                        await list.applyNow()
                        isApplying = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isApplying { ProgressView().controlSize(.mini) }
                        Text("Apply to the Open Chat")
                    }
                }
                .buttonStyle(.clickable(.bordered))
                .disabled(isApplying)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AppRow: View {
    let server: MCPServer
    let list: MCPServerList
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Plain, so a tap on the switch doesn't open the app too.
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: AppSymbol.name(for: server))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .foregroundStyle(server.enabled ? Theme.ink : Theme.secondaryInk)
                            .lineLimit(1, accessibility: 3)
                        // A problem shows whole: it says what to do next.
                        statusLine
                            .font(.subheadline)
                            .lineLimit(isProblem ? nil : 2)
                            .fixedSize(horizontal: false, vertical: isProblem)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.clickable)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Shows its tools and settings"))
            if server.isFromPlugin {
                Text("Plugin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help(Text("Comes with the \(server.plugin ?? "") plugin, so it can't be changed here"))
            } else {
                Toggle(
                    isOn: Binding(
                        get: { server.enabled },
                        set: { enabled in Task { await list.setEnabled(enabled, for: server) } })
                ) {
                    Text(server.name)
                }
                .labelsHidden()
            }
        }
    }

    /// Where it runs, then how it's doing: off, its tool count, or what went wrong.
    private var isProblem: Bool { AppStatus(server: server, list: list).isProblem }

    private var statusLine: Text {
        let location = Text(server.location).foregroundStyle(Theme.secondaryInk)
        let status = AppStatus(server: server, list: list)
        guard let words = status.words else { return location }
        let styled = Text(words).foregroundStyle(status.isProblem ? Theme.danger : Theme.secondaryInk)
        guard !server.location.isEmpty else { return styled }
        return Text("\(location)\(Text(" · ").foregroundStyle(Theme.secondaryInk))\(styled)")
    }
}

/// A server's state in a few words, shared by its row and its sheet.
@MainActor
struct AppStatus {
    let server: MCPServer
    let list: MCPServerList

    var words: String? {
        switch list.signIns[server.id] {
        case .starting, .waiting: return String(localized: "Signing in…")
        case .failed: return String(localized: "Sign-in didn't finish")
        case nil: break
        }
        if !server.enabled { return String(localized: "Off") }
        switch list.checks[server.id] {
        case .running: return String(localized: "Testing…")
        case .passed(let tools):
            return tools.count == 1 ? String(localized: "1 tool") : String(localized: "\(tools.count) tools")
        case .failed: return String(localized: "Didn't connect")
        case nil: return nil
        }
    }

    var isProblem: Bool {
        if case .failed = list.signIns[server.id] { return true }
        if server.enabled, case .failed = list.checks[server.id] { return true }
        return false
    }
}

enum AppSymbol {
    static func name(for server: MCPServer) -> String {
        if server.isFromPlugin { return "puzzlepiece.extension" }
        return server.url != nil ? "globe" : "terminal"
    }
}
