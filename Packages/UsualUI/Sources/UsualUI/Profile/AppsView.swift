import HermesKit
import SwiftUI

/// The agent's apps: the MCP servers its profile uses, each with a switch. Opening one shows its
/// tools; New App brings one in from Hermes's catalog or by address.
struct AppsView: View {
    let list: MCPServerList
    var connectors: ConnectorList? = nil
    let agentName: String

    @State private var selected: MCPServer?
    @State private var isAdding = false
    /// A server just added that wants signing in, opened once the add sheet has gone.
    @State private var openAfterAdding: MCPServer.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch list.phase {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 20)
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await list.refresh() } }
                        .buttonStyle(.clickable)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .frame(maxWidth: .infinity)
            case .ready:
                servers
            }
            Text(
                "Apps connect \(agentName) to other services through MCP servers on your gateway. Hermes runs them, and \(agentName) uses their tools in chat."
            )
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
            if let connectors { ConnectorsSection(list: connectors, agentName: agentName) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: list.profile) { await list.refresh() }
        .sheet(item: $selected) { AppDetailSheet(list: list, server: $0, agentName: agentName) }
        .sheet(isPresented: $isAdding, onDismiss: openAddedServer) {
            AppAddSheet(list: list) { openAfterAdding = $0 }
        }
    }

    private var servers: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Connected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button {
                    isAdding = true
                } label: {
                    Label("New App", systemImage: "plus")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.primaryInk)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(Theme.primary, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.clickable)
                .fixedSize()
            }
            .padding(.bottom, 6)
            if list.needsApply { ApplyNote(list: list, agentName: agentName).padding(.vertical, 8) }
            if list.servers.isEmpty {
                Text("No apps yet. Add one to give \(agentName) more tools.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.vertical, 8)
            }
            ForEach(list.servers) { server in
                AppRow(server: server, list: list) { selected = server }
                Divider().overlay(Theme.border)
            }
            if let notice = list.notice {
                Text(notice)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            if let problem = list.problem {
                Text(problem)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
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
                .foregroundStyle(Theme.ink)
            if list.canApplyNow {
                Text(
                    "To use it in the open chat now, apply it. \(agentName)'s next reply costs more, since the whole conversation is sent again."
                )
                .foregroundStyle(Theme.secondaryInk)
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
                .buttonStyle(CardButtonStyle(primary: false))
                .disabled(isApplying)
            }
        }
        .font(.system(size: 12.5))
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.pane, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }
}

private struct AppRow: View {
    let server: MCPServer
    let list: MCPServerList
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: AppSymbol.name(for: server))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.system(size: 14))
                            .foregroundStyle(server.enabled ? Theme.ink : Theme.secondaryInk)
                            .lineLimit(1)
                        // A problem shows whole: it says what to do next.
                        statusLine
                            .font(.system(size: 12.5))
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
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(Theme.selection, in: Capsule())
                    .help(Text("Comes with the \(server.plugin ?? "") plugin, so it can't be changed here"))
            } else {
                Toggle(
                    isOn: Binding(
                        get: { server.enabled },
                        set: { enabled in Task { await list.setEnabled(enabled, for: server) } })
                ) {
                    Text(server.name)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.ink)
            }
        }
        .padding(.vertical, 9)
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
