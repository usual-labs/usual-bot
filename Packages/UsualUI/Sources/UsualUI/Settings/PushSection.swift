import HermesKit
import SwiftUI

/// Push on this device: whether the gateway can reach it, and which Bots it hears from.
struct PushSection: View {
    let push: PushSettings
    let bots: [Contact]
    let choices: PushSettings.Choices

    @State private var isBusy = false
    @State private var result: String?
    @State private var problem: String?

    private static let guide = URL(
        string: "https://github.com/usual-labs/usual-bot/tree/main/Integrations/hermes-push")!

    var body: some View {
        Section {
            switch push.phase {
            case .loading:
                Text("Checking your gateway…").foregroundStyle(Theme.secondaryInk)
            case .notInstalled:
                Text("Your gateway doesn’t have the Usual Bot push plugin yet.")
                Link("How to install it", destination: Self.guide)
            case .failed(let reason):
                Text(reason).foregroundStyle(Theme.danger)
                Button("Try Again") { Task { await push.refresh() } }
            case .ready:
                ready
            }
        } header: {
            Text("Push")
        } footer: {
            Text(
                "Reach this device even when Usual Bot is closed. Your gateway seals each notification for this device alone; Usual’s relay and Apple only pass it on."
            )
        }
        .onChange(of: choices) { _, choices in
            guard push.isActive else { return }
            run { try await push.save(choices) }
        }
        if push.isActive, !bots.isEmpty {
            Section {
                ForEach(bots) { bot in
                    Toggle(bot.name, isOn: heard(bot))
                }
            } header: {
                Text("Bots on this device")
            } footer: {
                Text("Turning a Bot off here keeps it quiet on this device only.")
            }
        }
    }

    @ViewBuilder private var ready: some View {
        if !push.isAvailable {
            Text("This copy of Usual Bot can’t receive push notifications. The TestFlight version can.")
                .foregroundStyle(Theme.secondaryInk)
        } else if !push.isConnected {
            Text("Adding this device to your gateway…").foregroundStyle(Theme.secondaryInk)
        } else {
            LabeledContent("This device", value: String(localized: "Gets notifications"))
            Button("Send Test") {
                run {
                    try await push.sendTest()
                    result = String(localized: "Sent. It should arrive in a moment.")
                }
            }
            .disabled(isBusy)
        }
        if let result { Text(result).foregroundStyle(Theme.secondaryInk) }
        if let problem { Text(problem).foregroundStyle(Theme.danger) }
    }

    private func heard(_ bot: Contact) -> Binding<Bool> {
        Binding(
            get: { !push.muted.contains(bot.id) },
            set: { on in run { try await push.setMuted(bot.id, !on) } })
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isBusy = true
        result = nil
        problem = nil
        Task {
            defer { isBusy = false }
            do {
                try await action()
            } catch {
                problem = AppModel.describe(error)
            }
        }
    }
}
