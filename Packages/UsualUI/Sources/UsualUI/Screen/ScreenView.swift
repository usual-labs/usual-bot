import HermesKit
import SwiftUI

/// An agent's computer, live: who's in control along the top, the screen below, scaled to fit.
/// A Mac window of its own; a full-screen cover on iPhone.
struct ScreenView: View {
    let contact: Contact
    let screen: BotScreen
    /// The agent's chat, to say when it's working while you're in control.
    let thread: ChatThread?
    var close: (() -> Void)? = nil

    @Environment(\.gatewayOnline) private var isOnline
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsKeyboard = false

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            stage
        }
        .background(Theme.window)
        .task(id: contact.id) {
            await screen.refresh()
            if screen.status?.running == true, screen.connection == .idle { screen.connect() }
        }
        .onDisappear { screen.disconnect() }
        // iOS cuts the socket in the background; come back to a live picture.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, case .failed = screen.connection { screen.connect() }
        }
        .onChange(of: screen.control) { _, control in
            if control != .you { showsKeyboard = false }
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let close {
                    Button("Close", systemImage: "xmark", action: close)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.clickable)
                        .frame(width: 32, height: 32)
                }
                controlPill
                Spacer(minLength: 8)
                if screen.status?.running == true, screen.hasScreen { controlButtons }
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = screen.problem {
                Text(problem).scaledFont(size: 12).foregroundStyle(Theme.danger)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlPill: some View {
        let (text, tint): (LocalizedStringKey, Color) =
            switch screen.control {
            case .you: ("You're in control", Theme.danger)
            case .someoneElse: ("Someone else is in control", Theme.needsYouInk)
            case .agent:
                thread?.state.isUsingComputer == true
                    ? ("\(contact.name) is using it", Theme.online)
                    : ("\(contact.name) is in control", Theme.secondaryInk)
            }
        return HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(text).scaledFont(size: 13, weight: .medium).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.selection, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var controlButtons: some View {
        #if os(iOS)
            if screen.control == .you {
                Button("Keyboard", systemImage: showsKeyboard ? "keyboard.chevron.compact.down" : "keyboard") {
                    showsKeyboard.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.clickable)
                .frame(width: 32, height: 32)
            }
        #endif
        if screen.control == .you {
            Button("Hand Back") { Task { await screen.handBack() } }
                .buttonStyle(CardButtonStyle(primary: false))
                .disabled(screen.isBusy || !isOnline)
                .accessibilityHint(Text("Gives control of the computer back to \(contact.name)"))
        } else {
            Button("Take Over") { Task { await screen.takeOver() } }
                .buttonStyle(CardButtonStyle(primary: true))
                .disabled(screen.isBusy || !isOnline || screen.connection != .live)
                .accessibilityHint(Text("Lets you use the computer; \(contact.name) waits until you hand it back"))
        }
    }

    /// What's worth knowing under the bar, most pressing first.
    private var lines: [String] {
        var lines: [String] = []
        if !isOnline {
            lines.append(String(localized: "Offline. The screen may be out of date until the gateway is back."))
        }
        if let notice = screen.notice { lines.append(notice) }
        if let reason = screen.lease?.reason, !reason.isEmpty, screen.lease?.holder == .human {
            lines.append(String(localized: "\(contact.name) asked: \(reason)"))
        }
        if screen.control == .you {
            if thread?.state.isRunning == true {
                lines.append(String(localized: "\(contact.name) waits to use the computer until you hand it back."))
            }
            if screen.isUnencrypted {
                lines.append(
                    String(
                        localized:
                            "This gateway's connection isn't encrypted, so others on your network could see what you type."
                    ))
            }
        }
        return lines
    }

    // MARK: - Screen

    @ViewBuilder private var stage: some View {
        if let status = screen.status, !screen.hasScreen {
            message(
                status.supported
                    ? "\(contact.name)'s computer isn't set up on the gateway."
                    : "\(contact.name) has no computer to show.")
        } else if let status = screen.status, !status.running {
            VStack(spacing: 12) {
                Text("The computer is off").scaledFont(size: 15, weight: .semibold).foregroundStyle(Theme.ink)
                Text(
                    status.blocker
                        ?? String(
                            localized: "Turn it on to watch what \(contact.name) does, and take over when it needs you."
                        )
                )
                .scaledFont(size: 13)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
                Button("Turn On") { Task { await screen.start() } }
                    .buttonStyle(CardButtonStyle(primary: true))
                    .disabled(screen.isBusy || status.blocker != nil || !isOnline)
                if screen.isBusy { ProgressView().controlSize(.small) }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                Color.black
                if let frame = screen.frame {
                    ScreenCanvas(screen: screen, frame: frame, showsKeyboard: $showsKeyboard)
                        .opacity(screen.connection == .live ? 1 : 0.4)
                        .overlay {
                            if screen.control == .you {
                                Rectangle().strokeBorder(Theme.danger.opacity(0.8), lineWidth: 2).allowsHitTesting(
                                    false)
                            }
                        }
                }
                connectionOverlay
            }
        }
    }

    @ViewBuilder private var connectionOverlay: some View {
        switch screen.connection {
        case .connecting:
            label {
                ProgressView().controlSize(.small).tint(.white)
            } text: {
                Text("Connecting to the computer…")
            }
        case .failed(let reason):
            VStack(spacing: 10) {
                Text(reason).multilineTextAlignment(.center)
                Button("Try Again") { screen.connect() }
                    .buttonStyle(CardButtonStyle(primary: true))
                    .disabled(!isOnline)
            }
            .padding(20)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .scaledFont(size: 13)
        case .idle where screen.status == nil:
            label {
                ProgressView().controlSize(.small).tint(.white)
            } text: {
                Text("Checking the computer…")
            }
        case .idle:
            Button("Watch") { screen.connect() }.buttonStyle(CardButtonStyle(primary: true)).disabled(!isOnline)
        case .live:
            EmptyView()
        }
    }

    private func label(@ViewBuilder icon: () -> some View, @ViewBuilder text: () -> Text) -> some View {
        HStack(spacing: 8) {
            icon()
            text()
        }
        .scaledFont(size: 13)
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .scaledFont(size: 13)
            .foregroundStyle(Theme.secondaryInk)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Mac's window for an agent's computer (`WindowGroup(id: "bot-screen", for: Contact.ID.self)`).
public struct BotScreenWindow: View {
    let model: AppModel
    let contactID: Contact.ID

    public init(model: AppModel, contactID: Contact.ID) {
        self.model = model
        self.contactID = contactID
    }

    public var body: some View {
        if let contact = model.contacts.first(where: { $0.id == contactID }) {
            ScreenView(contact: contact, screen: model.screen(for: contact), thread: model.thread(for: contact))
                .environment(\.gatewayOnline, model.isOnline)
                .navigationTitle(Text("\(contact.name)'s Computer"))
                .frame(minWidth: 480, minHeight: 360)
        } else {
            Text("This Bot isn't on the gateway anymore.")
                .foregroundStyle(Theme.secondaryInk)
                .frame(minWidth: 480, minHeight: 360)
        }
    }
}

extension AppModel {
    var isOnline: Bool {
        if case .online = link { return true }
        return false
    }
}

extension EnvironmentValues {
    /// The app's socket to the gateway is up.
    @Entry var gatewayOnline = true
    /// Where the chat finds its agent's computer (`AppModel.screen(for:)`).
    @Entry var screens: AppModel?
}
