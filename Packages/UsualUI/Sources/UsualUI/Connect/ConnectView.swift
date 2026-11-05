import HermesKit
import SwiftUI

/// First run: type the gateway's address, then finish signing in in the browser. `options` are
/// the app's own settings for reaching it, such as the iPhone's built-in Tailscale.
struct ConnectView<Options: View>: View {
    @Bindable var model: AppModel
    let presenter: any SignInPresenter
    @ViewBuilder let options: () -> Options

    @FocusState private var addressFocused: Bool

    var body: some View {
        // A form scrolls, so the keyboard can't hide the button or a problem under the field.
        Form {
            Section {
            } header: {
                heading
            }
            if case .signingIn(let gateway) = model.session {
                Section { waiting(for: gateway) }
            } else {
                Section {
                    TextField(
                        "Gateway address", text: $model.gatewayInput,
                        prompt: Text("100.64.0.1:9119 or hermes.example.com")
                    )
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                    .focused($addressFocused)
                    .onSubmit(signIn)
                    options()
                } footer: {
                    if let problem = model.problem {
                        Text(problem).foregroundStyle(Theme.danger)
                    }
                }
                Section {
                } footer: {
                    signInButton
                }
            }
            Section {
            } footer: {
                Text("An independent app, not made by or affiliated with Nous Research.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .onAppear { addressFocused = true }
    }

    private var heading: some View {
        VStack(spacing: 6) {
            HermesMark().frame(width: 96, height: 96).padding(.bottom, 18)
            Text("Connect to Hermes")
                .scaledFont(size: 22, weight: .semibold)
                .foregroundStyle(Theme.ink)
            Text("Sign in to your Hermes gateway to see your Bots.")
                .scaledFont(size: 14)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .textCase(nil)
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 8)
    }

    private var signInButton: some View {
        Button(action: signIn) {
            Text("Sign in with browser")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.inkProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(model.gatewayInput.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func waiting(for gateway: GatewayAddress) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text("Finish signing in to \(gateway.displayName) in your browser.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel", action: model.cancelSignIn)
                .buttonStyle(.clickable(.bordered))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
