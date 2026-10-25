import HermesKit
import SwiftUI

/// First run: type the gateway's address, then finish signing in in the browser.
struct ConnectView: View {
    @Bindable var model: AppModel
    let presenter: any SignInPresenter

    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            mark
            VStack(spacing: 6) {
                Text("Connect to Hermes")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Sign in to your Hermes gateway to see your agents.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            if case .signingIn(let gateway) = model.session {
                waiting(for: gateway)
            } else {
                form
            }
        }
        .frame(maxWidth: 380)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
    }

    private var form: some View {
        VStack(spacing: 12) {
            TextField(
                "Gateway address", text: $model.gatewayInput, prompt: Text("100.64.0.1:9119 or hermes.example.com")
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
            .focused($addressFocused)
            .onSubmit(signIn)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Theme.pane, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))

            Button(action: signIn) {
                Text("Sign in with browser")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Theme.primaryInk)
                    .background(Theme.primary, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.gatewayInput.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(model.gatewayInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)

            if let problem = model.problem {
                Text(problem)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { addressFocused = true }
    }

    private func waiting(for gateway: GatewayAddress) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text("Finish signing in to \(gateway.displayName) in your browser.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
            Button("Cancel", action: model.cancelSignIn)
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 44)
        }
    }

    private var mark: some View {
        HermesMark().frame(width: 96, height: 96)
    }

    private func signIn() {
        guard !model.gatewayInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.signIn(presenter: presenter)
    }
}

/// The Hermes doodle, the app's icon character, drawn without a background.
struct HermesMark: View {
    var body: some View {
        (AvatarArt.resource("hermes-mark") ?? Image(systemName: "person.crop.circle"))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

/// What shows while the app reads the saved sign-in at launch: the mark on the window colour,
/// where the iPhone launch screen put it, so launching looks like one still picture.
struct SplashView: View {
    var body: some View {
        HermesMark()
            .frame(width: 120, height: 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.window)
            .ignoresSafeArea()
    }
}
