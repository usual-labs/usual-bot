import HermesKit
import SwiftUI

/// The apps the agent reaches through your Nous Portal account (Hermes's hosted connectors), on
/// the Apps page under its MCP servers. Shown only when the gateway offers them. The Apps page
/// loads it: a section can be empty, with no view to hang a load on.
struct ConnectorsSection: View {
    let list: ConnectorList
    let agentName: String

    var body: some View {
        switch list.phase {
        case .loading, .unavailable:
            EmptyView()
        case .failed(let message):
            Section("Connected accounts") {
                ProfileFailure(message: message) { await list.refresh() }
            }
        case .ready:
            Section {
                if list.connectors.isEmpty {
                    Text("No apps to connect yet.").foregroundStyle(.secondary)
                }
                ForEach(list.connectors) { connector in
                    ConnectorRow(connector: connector, list: list)
                }
                if let notice = list.notice {
                    Text(notice).foregroundStyle(.secondary)
                }
                if let problem = list.problem {
                    Text(problem).foregroundStyle(Theme.danger)
                }
            } header: {
                Text("Connected accounts")
            } footer: {
                Text(
                    "These sign in through your Nous Portal account, which Hermes uses for \(agentName). \(agentName) can also ask to connect one from the chat."
                )
            }
        }
    }
}

private struct ConnectorRow: View {
    let connector: ConnectorList.Connector
    let list: ConnectorList

    @State private var confirmsDisconnect = false
    private var page = SignInPage()

    init(connector: ConnectorList.Connector, list: ConnectorList) {
        self.connector = connector
        self.list = list
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(connector.name.prefix(1)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .background(Theme.selection, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(connector.name)
                    .lineLimit(1, accessibility: 3)
                if let status {
                    // A problem shows whole: it says what to do next.
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(isProblem ? Theme.danger : Theme.secondaryInk)
                        .lineLimit(isProblem ? nil : 2)
                        .fixedSize(horizontal: false, vertical: isProblem)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            action.controlSize(.small)
        }
        .onChange(of: connector.isConnected) { page.close() }
        .onChange(of: list.connecting[connector.id] == nil) { page.close() }
        .confirmationDialog(
            "Disconnect \(connector.name)?", isPresented: $confirmsDisconnect, titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) { Task { await list.disconnect(connector) } }
        } message: {
            Text("The account is removed from your Nous Portal, so every Bot that uses it loses it.")
        }
    }

    @ViewBuilder private var action: some View {
        switch list.connecting[connector.id] {
        case .starting:
            ProgressView().accessibilityLabel(Text("Connecting \(connector.name)"))
        case .waiting:
            Button("Stop") { Task { await list.cancelConnecting(connector) } }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Stop connecting \(connector.name)"))
        case .failed, nil:
            if list.disconnecting.contains(connector.id) {
                ProgressView().accessibilityLabel(Text("Disconnecting \(connector.name)"))
            } else if connector.isConnected {
                Button("Disconnect") { confirmsDisconnect = true }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Disconnect \(connector.name)"))
            } else {
                Button("Connect") { Task { await list.connect(connector) { page.open($0) } } }
                    .buttonStyle(.inkProminent)
                    .accessibilityLabel(Text("Connect \(connector.name)"))
            }
        }
    }

    private var isProblem: Bool {
        if case .failed = list.connecting[connector.id] { return true }
        return connector.statusReason != nil && !connector.isConnected
    }

    private var status: String? {
        switch list.connecting[connector.id] {
        case .starting: return String(localized: "Getting the sign-in page…")
        case .waiting: return String(localized: "Waiting for you to finish signing in…")
        case .failed(let reason): return reason
        case nil:
            if connector.isConnected { return String(localized: "Connected") }
            return connector.statusReason ?? connector.summary
        }
    }
}
