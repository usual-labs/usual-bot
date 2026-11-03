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
                Text("Checking your gateway…").foregroundStyle(Theme.secondaryInk)
            case .notInstalled:
                Text("Your gateway doesn’t have the Usual Bot push plugin yet.")
                Link("How to install it", destination: Self.guide)
            case .failed(let reason):
                Text(reason).foregroundStyle(Theme.danger)
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
            PushField("Server", text: $push.server, prompt: "https://ntfy.sh")
            PushField("Topic", text: $push.topic, prompt: "Required")
            PushField("Access token", text: $ntfyToken, prompt: push.hasNtfyToken ? "Saved" : "Optional", secret: true)
        case .pushover:
            PushField("User key", text: $userKey, prompt: push.hasUserKey ? "Saved" : "Required", secret: true)
            PushField("Application token", text: $token, prompt: push.hasToken ? "Saved" : "Required", secret: true)
        }
        if gatewayIsUnencrypted, push.service != .off {
            Text("Your gateway connection isn’t encrypted, so these could be read on the way there.")
                .foregroundStyle(Theme.needsYouInk)
        }
        #if os(iOS)
            // Rows of their own: two buttons in one row of a list both run on a tap.
            saveButton
            if push.service != .off { testButton }
        #else
            HStack {
                saveButton
                if push.service != .off { testButton }
            }
        #endif
        if let result { Text(result).foregroundStyle(Theme.secondaryInk) }
        if let problem { Text(problem).foregroundStyle(Theme.danger) }
    }

    private var saveButton: some View {
        Button("Save") { run { try await save() } }.disabled(isBusy)
    }

    private var testButton: some View {
        Button("Send Test") {
            run {
                try await push.saveAndSendTest(changes)
                clearSecrets()
                result = String(localized: "Sent through \(serviceName). It should arrive in a moment.")
            }
        }
        .disabled(isBusy)
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

/// A labelled field: on iPhone a bare field's name goes once something is typed in it.
private struct PushField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    let prompt: LocalizedStringKey
    var secret = false

    init(_ label: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey, secret: Bool = false) {
        self.label = label
        _text = text
        self.prompt = prompt
        self.secret = secret
    }

    var body: some View {
        #if os(iOS)
            LabeledContent(label) {
                field.multilineTextAlignment(.trailing)
            }
        #else
            field
        #endif
    }

    @ViewBuilder private var field: some View {
        if secret {
            SecureField(label, text: $text, prompt: Text(prompt))
        } else {
            TextField(label, text: $text, prompt: Text(prompt))
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
        }
    }
}
