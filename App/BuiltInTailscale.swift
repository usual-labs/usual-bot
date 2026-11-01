#if os(iOS)
    import Foundation
    import Observation
    import SwiftUI
    import Tailnet

    /// The app's own Tailscale device as the app shows it: whether it's on, its state, and the
    /// gateway menu's Tailscale actions. Shows Tailscale's sign-in page when the device needs it.
    @MainActor
    @Observable
    final class BuiltInTailscale {
        /// Gateway traffic goes through the device. Off, it takes the system's network, where a
        /// tailnet gateway needs the Tailscale app's VPN.
        private(set) var isOn: Bool
        private(set) var state = Tailnet.State.stopped
        /// The last Tailscale action that failed, for the menu.
        private(set) var problem: String?
        let tailnet: Tailnet
        @ObservationIgnored private let login = WebAuthSignInPresenter()
        @ObservationIgnored private let defaults: UserDefaults

        private static let key = "builtInTailscale"

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
            isOn = defaults.bool(forKey: Self.key)
            tailnet = Tailnet(
                directory: .applicationSupportDirectory.appending(path: "Tailscale", directoryHint: .isDirectory),
                hostName: "usual-bot-iphone", logFile: .cachesDirectory.appending(path: "tailscale.log"))
            Task { [weak self, states = tailnet.states] in
                for await state in states { self?.show(state) }
            }
        }

        /// The session for gateway traffic: through the device while it's on.
        func session() async throws -> URLSession {
            guard isOn else { return .shared }
            return try await tailnet.session()
        }

        /// Turns the device on or off. The gateway connection should reconnect afterwards.
        func setOn(_ on: Bool) {
            isOn = on
            defaults.set(on, forKey: Self.key)
            problem = nil
            if !on { Task { await tailnet.stop() } }
        }

        /// Shows Tailscale's sign-in page again, e.g. after it was closed unfinished.
        func signIn() {
            if case .needsLogin(let page) = state { login.present(page, onCancel: {}) }
        }

        /// Removes the device from the tailnet and turns it off.
        func signOut() async {
            do {
                try await tailnet.signOut()
                setOn(false)
            } catch {
                problem = String(localized: "Couldn't sign out: \(error.localizedDescription)")
            }
        }

        /// iOS cuts a suspended app's sockets, so the device stops in the background; the next
        /// gateway request starts it again.
        func suspend() {
            Task { await tailnet.suspend() }
        }

        private func show(_ state: Tailnet.State) {
            self.state = state
            if case .needsLogin(let page) = state, isOn {
                login.present(page, onCancel: {})
            } else {
                login.dismiss()
            }
        }
    }

    /// The gateway menu's Tailscale section: the switch, the device's state and its actions.
    struct TailscaleMenu: View {
        let tailscale: BuiltInTailscale
        /// Connects to the gateway again after the route to it changed.
        let reconnect: () -> Void

        var body: some View {
            Section("Tailscale") {
                Toggle(
                    "Built-in Tailscale",
                    isOn: Binding(
                        get: { tailscale.isOn },
                        set: {
                            tailscale.setOn($0)
                            reconnect()
                        }))
                if tailscale.isOn {
                    state
                } else {
                    Text("Off: a tailnet gateway needs the Tailscale VPN")
                }
                if let problem = tailscale.problem {
                    Text(problem)
                }
            }
        }

        @ViewBuilder private var state: some View {
            switch tailscale.state {
            case .stopped, .starting:
                Text("Starting…")
            case .needsLogin:
                Button("Sign In to Tailscale…", action: tailscale.signIn)
            case .running(let device):
                Text("Connected as \(device.name)\(device.address.map { " (\($0))" } ?? "")")
                Button("Sign Out of Tailscale", role: .destructive) {
                    Task {
                        await tailscale.signOut()
                        reconnect()
                    }
                }
            case .failed(let reason):
                Text("Couldn't start: \(reason)")
            }
        }
    }
#endif
