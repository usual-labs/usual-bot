#if os(macOS)
    import HermesKit
    import SwiftUI

    /// Show or Hide Terminal (⌘J) for the open chat.
    struct TerminalCommand {
        let isShown: Bool
        let toggle: () -> Void
    }

    extension FocusedValues {
        @Entry var terminal: TerminalCommand?
    }

    enum TerminalTab: String {
        case shell, commands
    }

    extension View {
        /// The terminal drawer along the bottom of a chat, under the message box: the agent's shell,
        /// and the commands it ran. Its height and tab are kept for every Bot.
        func terminalDrawer(
            isPresented: Bool, contact: Contact, terminal: BotTerminal?, thread: ChatThread?,
            hide: @escaping () -> Void
        ) -> some View {
            VStack(spacing: 0) {
                self
                if isPresented, let terminal {
                    TerminalDrawer(contact: contact, terminal: terminal, thread: thread, hide: hide)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.smooth(duration: 0.25), value: isPresented)
        }
    }

    struct TerminalDrawer: View {
        let contact: Contact
        let terminal: BotTerminal
        let thread: ChatThread?
        let hide: () -> Void

        static let heightKey = "terminalHeight"
        static let tabKey = "terminalTab"
        static let heightRange: ClosedRange<Double> = 120...700

        @AppStorage(Self.heightKey) private var height = 260.0
        @AppStorage(Self.tabKey) private var tab = TerminalTab.shell
        @State private var dragStart: Double?
        @FocusState private var shellFocused: Bool
        @Environment(\.gatewayOnline) private var isOnline

        var body: some View {
            VStack(spacing: 0) {
                header
                Rectangle().fill(TerminalStyle.divider).frame(height: 1)
                Group {
                    switch tab {
                    case .shell: shell
                    case .commands: BotCommandsView(agentName: contact.name, state: thread?.state)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: height)
            .background(TerminalStyle.background)
            .environment(\.colorScheme, .dark)
            .overlay(alignment: .top) { grip }
            .task(id: "\(contact.id) \(tab) \(isOnline) \(terminal.availability == .available)") { startShell() }
            .onAppear { if tab == .shell { shellFocused = true } }
        }

        // MARK: - Header

        private var header: some View {
            HStack(spacing: 6) {
                tabButton(.shell, title: Text("Shell"))
                tabButton(.commands, title: Text("\(contact.name)'s Commands"))
                if tab == .shell, let place = terminal.place {
                    Text(verbatim: Self.describe(place))
                        .font(Font(TerminalStyle.font(size: 11)))
                        .foregroundStyle(TerminalStyle.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(.leading, 6)
                }
                Spacer(minLength: 8)
                Button(action: hide) {
                    HStack(spacing: 4) {
                        Text("Hide")
                        Text(verbatim: "⌘J")
                            .font(.system(size: 10))
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(TerminalStyle.divider))
                    }
                    .foregroundStyle(TerminalStyle.secondaryInk)
                }
                .buttonStyle(.clickable)
                .help(Text("Hide Terminal"))
            }
            .scaledFont(size: 11)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(TerminalStyle.bar)
        }

        static func describe(_ place: BotTerminal.Place) -> String {
            let who = [place.user, place.host].compactMap { $0 }.joined(separator: "@")
            // The gateway's home folder, by the usual names, shortened as a prompt does.
            let folder = place.folder.map { folder in
                let homes = place.user.map { ["/home/\($0)", "/Users/\($0)"] } ?? []
                guard let home = homes.first(where: { folder == $0 || folder.hasPrefix($0 + "/") }) else {
                    return folder
                }
                return "~" + folder.dropFirst(home.count)
            }
            return [who.isEmpty ? nil : who, folder].compactMap { $0 }.joined(separator: ":")
        }

        private func tabButton(_ value: TerminalTab, title: Text) -> some View {
            Button {
                tab = value
                if value == .shell { shellFocused = true }
            } label: {
                title
                    .foregroundStyle(tab == value ? TerminalStyle.ink : TerminalStyle.secondaryInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        tab == value ? TerminalStyle.selectedTab : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.clickable)
            .accessibilityAddTraits(tab == value ? .isSelected : [])
        }

        /// The drawer's top edge: drag it to resize.
        private var grip: some View {
            Rectangle()
                .fill(Color.primary.opacity(0.001))
                .frame(height: 8)
                .overlay {
                    Capsule().fill(TerminalStyle.divider).frame(width: 36, height: 3).offset(y: -1)
                }
                .pointerStyle(.frameResize(position: .top))
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStart ?? height
                            dragStart = start
                            height = min(
                                max(start - drag.translation.height, Self.heightRange.lowerBound),
                                Self.heightRange.upperBound)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .accessibilityHidden(true)
        }

        // MARK: - Shell

        private func startShell() {
            guard tab == .shell, isOnline, terminal.availability == .available else { return }
            if case .idle = terminal.connection { terminal.start() }
        }

        @ViewBuilder private var shell: some View {
            if !isOnline, terminal.connection != .live {
                note("You're offline. The shell opens when the gateway is back.")
            } else {
                switch terminal.availability {
                case .unknown:
                    ProgressView().controlSize(.small)
                case .noPlugin:
                    note(
                        "Your gateway's usual-bot plugin has no shell yet.",
                        detail: "Update it from Plugins, the puzzle piece in the sidebar, then restart the gateway.")
                case .sandboxed(let backend):
                    note(
                        "\(contact.name) runs its commands in \(backend), not on the gateway's computer, so there's no shell to open here.",
                        detail: "\(contact.name)'s Commands shows what it ran.")
                case .available:
                    connected
                }
            }
        }

        @ViewBuilder private var connected: some View {
            switch terminal.connection {
            case .idle, .connecting:
                ProgressView().controlSize(.small)
            case .live:
                TerminalShellView(terminal: terminal, focus: $shellFocused)
            case .ended(let code):
                VStack(spacing: 0) {
                    TerminalShellView(terminal: terminal, focus: $shellFocused)
                    restartBar(code.map { "The shell ended (exit \($0))." } ?? "The shell ended.")
                }
            case .failed(let message):
                VStack(spacing: 10) {
                    Text(message).foregroundStyle(TerminalStyle.ink)
                    restartButton("Try Again")
                }
                .scaledFont(size: 12)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            }
        }

        private func restartBar(_ text: LocalizedStringKey) -> some View {
            HStack {
                Text(text).foregroundStyle(TerminalStyle.secondaryInk)
                Spacer()
                restartButton("New Shell")
            }
            .scaledFont(size: 11)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(TerminalStyle.bar)
        }

        private func restartButton(_ title: LocalizedStringKey) -> some View {
            Button(title) {
                terminal.start()
                shellFocused = true
            }
            .buttonStyle(.clickable(.bordered))
        }

        private func note(_ text: LocalizedStringKey, detail: LocalizedStringKey? = nil) -> some View {
            VStack(spacing: 6) {
                Text(text).foregroundStyle(TerminalStyle.ink)
                if let detail { Text(detail).foregroundStyle(TerminalStyle.secondaryInk) }
            }
            .scaledFont(size: 12)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
    }
#endif
