import HermesKit
import SwiftUI

/// The apps the agent reaches through your Nous Portal account (Hermes's hosted connectors), on
/// the Apps page under its MCP servers. Shown only when the gateway offers them.
struct ConnectorsSection: View {
    let list: ConnectorList
    let agentName: String

    @State private var confirming: ConnectorList.Connector?

    var body: some View {
        Group {
            switch list.phase {
            case .loading, .unavailable:
                EmptyView()
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    header
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") { Task { await list.refresh() } }
                        .buttonStyle(.clickable)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                }
                .padding(.top, 22)
            case .ready:
                rows.padding(.top, 22)
            }
        }
        .task(id: list.profile) { await list.refresh() }
        .confirmationDialog(
            confirming.map { "Disconnect \($0.name)?" } ?? "", isPresented: isConfirming, titleVisibility: .visible,
            presenting: confirming
        ) { connector in
            Button("Disconnect", role: .destructive) { Task { await list.disconnect(connector) } }
        } message: { _ in
            Text("The account is removed from your Nous Portal, so every agent that uses it loses it.")
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var header: some View {
        Text("Connected accounts")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.secondaryInk)
            .accessibilityAddTraits(.isHeader)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 6)
            if list.connectors.isEmpty {
                Text("No apps to connect yet.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.vertical, 8)
            }
            ForEach(list.connectors) { connector in
                ConnectorRow(connector: connector, list: list) { confirming = connector }
                Divider().overlay(Theme.border)
            }
            if let notice = list.notice {
                Text(notice)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.top, 10)
            }
            if let problem = list.problem {
                Text(problem)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            Text(
                "These sign in through your Nous Portal account, which Hermes uses for \(agentName). \(agentName) can also ask to connect one from the chat."
            )
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
        }
    }
}

private struct ConnectorRow: View {
    let connector: ConnectorList.Connector
    let list: ConnectorList
    let disconnect: () -> Void

    private var page = SignInPage()

    init(connector: ConnectorList.Connector, list: ConnectorList, disconnect: @escaping () -> Void) {
        self.connector = connector
        self.list = list
        self.disconnect = disconnect
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
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let status {
                    Text(status)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isProblem ? Theme.danger : Theme.secondaryInk)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 9)
        .onChange(of: connector.isConnected) { page.close() }
        .onChange(of: list.connecting[connector.id] == nil) { page.close() }
    }

    @ViewBuilder private var action: some View {
        switch list.connecting[connector.id] {
        case .starting:
            ProgressView().controlSize(.small).accessibilityLabel(Text("Connecting \(connector.name)"))
        case .waiting:
            Button("Stop") { Task { await list.cancelConnecting(connector) } }
                .buttonStyle(CardButtonStyle(primary: false))
                .accessibilityLabel(Text("Stop connecting \(connector.name)"))
        case .failed, nil:
            if list.disconnecting.contains(connector.id) {
                ProgressView().controlSize(.small).accessibilityLabel(Text("Disconnecting \(connector.name)"))
            } else if connector.isConnected {
                Button("Disconnect", action: disconnect)
                    .buttonStyle(CardButtonStyle(primary: false))
                    .accessibilityLabel(Text("Disconnect \(connector.name)"))
            } else {
                Button("Connect") { Task { await list.connect(connector) { page.open($0) } } }
                    .buttonStyle(CardButtonStyle(primary: true))
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
