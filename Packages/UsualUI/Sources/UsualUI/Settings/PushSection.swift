import HermesKit
import SwiftUI

/// Sets up the gateway to reach you through ntfy or Pushover.
struct PushSection: View {
    @Bindable var push: PushSettings
    let gatewayIsUnencrypted: Bool
    let messages: Bool
    let needsYou: Bool
    let previews: Bool

    @State private var ntfyToken = ""
    @State private var token = ""
    @State private var userKey = ""
    @State private var isBusy = false
    @State private var result: String?
    @State private var problem: String?

    private static let guide = URL(
        string: "https://github.com/usual-labs/usual-bot/tree/main/Integrations/hermes-push")!

    var body: some View {
        Section {
            switch push.phase {
            case .loading:
                Text("Checking your gateway…").foregroundStyle(.secondary)
            case .notInstalled:
                Text("Your gateway doesn’t have the Usual Bot push plugin yet.")
                Link("How to install it", destination: Self.guide)
            case .failed(let reason):
                Text(reason).foregroundStyle(.red)
                Button("Try Again") { Task { await push.refresh() } }
            case .ready:
                form
            }
        } header: {
            Text("Push")
        } footer: {
            Text(
                "Reach you anywhere, even when Usual Bot is closed. Your gateway sends these through the service you pick, using that service’s own app, so anything in a preview passes through it."
            )
        }
        .onChange(of: messages) { saveChoices() }
        .onChange(of: needsYou) { saveChoices() }
        .onChange(of: previews) { saveChoices() }
    }

    @ViewBuilder private var form: some View {
        Picker("Service", selection: $push.service) {
            Text("Off").tag(PushSettings.Service.off)
            Text("ntfy").tag(PushSettings.Service.ntfy)
            Text("Pushover").tag(PushSettings.Service.pushover)
        }
        switch push.service {
        case .off:
            EmptyView()
        case .ntfy:
            TextField("Server", text: $push.server).autocorrectionDisabled()
            TextField("Topic", text: $push.topic).autocorrectionDisabled()
            SecureField(
                push.hasNtfyToken ? "Access token (saved)" : "Access token (optional)", text: $ntfyToken)
        case .pushover:
            SecureField(push.hasUserKey ? "User key (saved)" : "User key", text: $userKey)
            SecureField(push.hasToken ? "Application token (saved)" : "Application token", text: $token)
        }
        if gatewayIsUnencrypted, push.service != .off {
            Text("Your gateway connection isn’t encrypted, so these could be read on the way there.")
                .foregroundStyle(.orange)
        }
        HStack {
            Button("Save") { run { try await save() } }
            if push.service != .off {
                Button("Send Test") {
                    run {
                        try await push.saveAndSendTest(changes)
                        clearSecrets()
                        result = String(localized: "Sent through \(serviceName). It should arrive in a moment.")
                    }
                }
            }
        }
        .disabled(isBusy)
        if let result { Text(result).foregroundStyle(.secondary) }
        if let problem { Text(problem).foregroundStyle(.red) }
    }

    private var serviceName: String { push.service == .pushover ? "Pushover" : "ntfy" }

    private var changes: PushSettings.Changes {
        PushSettings.Changes(
            ntfyToken: ntfyToken.isEmpty ? nil : ntfyToken, token: token.isEmpty ? nil : token,
            userKey: userKey.isEmpty ? nil : userKey, messages: messages, needsYou: needsYou, previews: previews)
    }

    private func clearSecrets() {
        ntfyToken = ""
        token = ""
        userKey = ""
    }

    private func save() async throws {
        try await push.save(changes)
        clearSecrets()
        result = String(localized: "Saved on your gateway.")
    }

    private func saveChoices() {
        guard push.phase == .ready else { return }
        run { try await push.save(changes) }
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
