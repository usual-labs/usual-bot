import HermesKit
import SwiftUI

/// The agent asking to connect apps, answered right in the chat: Connect opens each app's sign-in
/// page, and Hermes moves the row when the vendor says you're done. The agent's reply waits until
/// every app is connected or skipped, or five minutes pass.
struct ConnectCard: View {
    let thread: ChatThread
    let card: ConnectionCard
    let agentName: String

    private var page = SignInPage()

    private var request: ConnectionRequest { card.request }
    private var canAnswer: Bool { thread.isAttached }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title)
                    .scaledFont(size: 13.5, weight: .medium)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "link")
                    .foregroundStyle(Theme.needsYouInk)
            }
            if request.isList {
                listBody
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(request.targets.enumerated()), id: \.element.id) { index, target in
                        if index > 0 { Divider().overlay(Theme.border) }
                        ConnectRow(
                            target: target, isOpened: card.opened.contains(target.name),
                            isBusy: card.busy.contains(target.name), canAnswer: canAnswer,
                            connect: { connect(target) }, retry: { thread.retry(target) })
                    }
                }
                .padding(.horizontal, 12)
                .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(note)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !canAnswer {
                Text("Reconnecting to the gateway. You can answer once it's back.")
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = card.problem {
                Text(problem)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if request.isList {
                    Button("Done", action: thread.finishConnecting)
                        .cardButton(prominent: true)
                } else {
                    Button("Not now", action: thread.skipConnection)
                        .cardButton()
                        .accessibilityHint(Text("\(agentName) goes on without these apps"))
                }
            }
            .disabled(!canAnswer)
        }
        .cardSurface()
        .onChange(of: request.targets.filter { $0.state == .connected }.count) { page.close() }
        .onDisappear { page.close() }
    }

    private func connect(_ target: ConnectionRequest.Target) {
        if let url = thread.connect(target) { page.open(url) }
    }

    private var title: String {
        if request.isList { return String(localized: "\(agentName) wants you to connect apps") }
        let names = request.targets.map(\.title).formatted(.list(type: .and))
        return String(localized: "\(agentName) wants to connect \(names)")
    }

    private var note: LocalizedStringKey {
        let notes = request.targets.compactMap(\.instructions)
        if let first = notes.first { return "\(first)" }
        if request.targets.allSatisfy({ $0.kind == .mcp }) {
            return "You sign in on the app's own page. Hermes keeps the sign-in on your gateway for \(agentName)."
        }
        return "You sign in on the app's own page. Hermes keeps the account in your Nous Portal for \(agentName)."
    }

    @ViewBuilder private var listBody: some View {
        if let suggested = request.suggested, !suggested.isEmpty {
            Text("Suggested: \(suggested.formatted(.list(type: .and)))")
                .scaledFont(size: 13)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("Connect them on \(agentName)'s Apps page, then choose Done.")
            .scaledFont(size: 12.5)
            .foregroundStyle(Theme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One app on the card: its name, where it's at, and the one thing you can do about it.
private struct ConnectRow: View {
    let target: ConnectionRequest.Target
    let isOpened: Bool
    let isBusy: Bool
    let canAnswer: Bool
    let connect: () -> Void
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(String(target.title.prefix(1)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                    .scaledFont(size: 14)
                    .foregroundStyle(Theme.ink)
                if let status {
                    Text(status)
                        .scaledFont(size: 12.5)
                        .foregroundStyle(isProblem ? Theme.danger : Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            action.fixedSize()
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder private var action: some View {
        if isBusy {
            ProgressView().controlSize(.small)
                .accessibilityLabel(Text("Sending"))
        } else {
            switch target.offer {
            case .signIn:
                Button(isOpened ? "Open Again" : "Connect", action: connect)
                    .cardButton(prominent: !isOpened)
                    .accessibilityLabel(
                        Text(isOpened ? "Open \(target.title) sign-in again" : "Connect \(target.title)")
                    )
                    .disabled(!canAnswer)
            case .approve:
                Button("Connect", action: connect)
                    .cardButton(prominent: true)
                    .accessibilityLabel(Text("Connect \(target.title)"))
                    .disabled(!canAnswer)
            case .retry:
                Button("Try Again", action: retry)
                    .cardButton()
                    .accessibilityLabel(Text("Try connecting \(target.title) again"))
                    .disabled(!canAnswer)
            case .preparing:
                ProgressView().controlSize(.small)
                    .accessibilityLabel(Text("Working"))
            case .elsewhere, .none:
                if target.state == .connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.online)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var isProblem: Bool { target.state == .failed || target.state == .expired }

    private var status: String? {
        switch target.state {
        case .connected: return String(localized: "Connected")
        case .skipped: return String(localized: "Not now")
        case .notConnected: return String(localized: "Not connected")
        case .failed:
            if let detail = target.detail { return String(localized: "Couldn't connect: \(detail)") }
            return String(localized: "Couldn't connect. Try again.")
        case .expired: return String(localized: "The sign-in link expired. Try again.")
        case .pending, .initiated:
            switch target.offer {
            case .elsewhere:
                return target.needsCredentials
                    ? String(localized: "Needs details typed in. Set it up in the Hermes app.")
                    : String(localized: "Set this up in the Hermes app.")
            case .preparing:
                // An MCP install or switch-on works on the gateway; a sign-in waits for its page.
                return target.kind == .mcp && target.action != "authorize"
                    ? String(localized: "Connecting…") : String(localized: "Getting the sign-in page…")
            case .signIn where isOpened: return String(localized: "Waiting for you to finish signing in…")
            default: return target.detail
            }
        }
    }
}
