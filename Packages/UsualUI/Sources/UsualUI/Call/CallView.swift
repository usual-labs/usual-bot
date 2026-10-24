import AVFoundation
import HermesKit
import SwiftUI

/// The call, as a glass bar over the top of the chat (the conversation keeps scrolling behind
/// it): the agent, its voice as dots, settings, transcript, mute and end. Settings and the
/// transcript open as a panel inside the bar. The engine is on-device speech (`VoiceCall`) or
/// GPT-Live (`LiveCall`), as the settings or the agent's gateway choose.
struct CallBar: View {
    let contact: Contact
    let end: () -> Void
    @State private var call: any CallEngine
    @State private var panel: Panel?
    /// Whether GPT-Live can run for this agent; `nil` until the gateway answers.
    @State private var liveStatus: VoiceLiveStatus?
    /// Set when the chosen engine can't run, e.g. GPT-Live without an OpenAI key on the gateway.
    @State private var engineProblem: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.voiceLive) private var voiceLive

    enum Panel {
        case settings, transcript
    }

    init(contact: Contact, thread: ChatThread, end: @escaping () -> Void) {
        self.contact = contact
        self.end = end
        _call = State(initialValue: VoiceCall(thread: thread))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.gap) {
                AgentAvatar(contact: still, size: 40)
                VoiceDots(levels: call.levels, speaking: call.phase == .speaking, tint: tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement()
                    .accessibilityLabel(Text(status))
                CallBarButton(
                    systemImage: "gearshape", label: String(localized: "Call settings"), active: panel == .settings
                ) { toggle(.settings) }
                CallBarButton(
                    systemImage: "ellipsis.bubble", label: String(localized: "Transcript"), active: panel == .transcript
                ) { toggle(.transcript) }
                CallBarButton(
                    systemImage: call.muted ? "mic.slash" : "mic",
                    label: call.muted ? String(localized: "Unmute") : String(localized: "Mute"), active: call.muted
                ) { call.muted.toggle() }
                CallBarButton(
                    systemImage: "xmark", label: String(localized: "End call"), active: false, tint: Theme.danger,
                    ink: .white, action: hangUp
                )
                .keyboardShortcut(.cancelAction)
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.vertical, 10)

            if let problem {
                Divider().overlay(Theme.border)
                Text(problem)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            } else if let panel {
                Divider().overlay(Theme.border)
                switch panel {
                case .settings:
                    CallSettingsPanel(
                        live: call is LiveCall, liveStatus: liveStatus,
                        languageChanged: { (call as? VoiceCall)?.languageChanged() },
                        engineChanged: { Task { await restart() } })
                case .transcript: TranscriptPanel(call: call, agentName: contact.name)
                }
            }
        }
        // GPT-Live's media runs in a web view that has to be on screen.
        .background {
            if let live = call as? LiveCall { LiveCallHost(webView: live.webView) }
        }
        .frame(maxWidth: 680)
        .floatingSurface(in: RoundedRectangle(cornerRadius: 30))
        .padding(.horizontal, 16)
        .animation(.smooth(duration: 0.2), value: panel)
        .task { await begin() }
        .onDisappear { call.end() }
        // A call doesn't go on in the background.
        .onChange(of: scenePhase) { _, phase in if phase == .background { hangUp() } }
    }

    #if os(macOS)
        private static let gap: CGFloat = 12
    #else
        private static let gap: CGFloat = 8
    #endif

    private var still: Contact {
        var copy = contact
        copy.activity = .idle
        return copy
    }

    private var tint: Color {
        contact.tintColor(style: AvatarStyle(seed: contact.id, paletteCount: Theme.agentPalette.count))
    }

    private var problem: String? {
        if let engineProblem { return engineProblem }
        if case .failed(let message) = call.phase { return message }
        return nil
    }

    private var profile: String { contact.details?.profile ?? contact.id }

    /// Picks the engine and starts the call: GPT-Live when it's chosen (or, on Automatic, when the
    /// agent's gateway selects it) and the gateway can run it; on-device speech otherwise.
    private func begin() async {
        let choice = CallSettings.engine
        if choice != "apple", let voiceLive {
            liveStatus = try? await voiceLive.status(profile: profile)
        }
        let wantsLive = choice == "gpt-live" || (choice.isEmpty && liveStatus?.mode == "gpt-live")
        if wantsLive, let voiceLive, let liveStatus, liveStatus.available {
            call = LiveCall(thread: call.thread, profile: profile, service: voiceLive)
        } else if choice == "gpt-live" {
            engineProblem = String(
                localized:
                    "GPT-Live can't start: \(liveStatus?.reason ?? String(localized: "the gateway didn't answer")). Choose On-device in the call settings to talk anyway.")
            panel = .settings
            return
        }
        await call.start()
    }

    /// The engine setting changed: end this call and start one with the new engine.
    private func restart() async {
        call.end()
        engineProblem = nil
        call = VoiceCall(thread: call.thread)
        await begin()
    }

    private var status: String {
        switch call.phase {
        case .starting: String(localized: "Connecting")
        case .listening: call.muted ? String(localized: "Muted") : String(localized: "Listening")
        case .thinking:
            call.thread.approvals.isEmpty
                ? String(localized: "Thinking") : String(localized: "Waiting for your OK in the chat")
        case .speaking: String(localized: "\(contact.name) is speaking")
        case .ended: String(localized: "Call ended")
        case .failed(let message): message
        }
    }

    private func toggle(_ panel: Panel) {
        self.panel = self.panel == panel ? nil : panel
    }

    private func hangUp() {
        call.end()
        end()
    }
}

/// The voice as a row of dots: your loudness while listening, a gentle wave while the agent talks.
private struct VoiceDots: View {
    let levels: [Double]
    let speaking: Bool
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !speaking)) { context in
            HStack(spacing: 4) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(tint.opacity(height(index, at: context.date) > 4 ? 1 : 0.55))
                        .frame(width: 4, height: height(index, at: context.date))
                }
            }
            .frame(height: 26)
            .animation(.easeOut(duration: 0.1), value: levels)
        }
    }

    private func height(_ index: Int, at date: Date) -> CGFloat {
        if speaking {
            let phase = date.timeIntervalSinceReferenceDate * 6 + Double(index) * 0.7
            return 4 + 14 * (0.5 + 0.5 * sin(phase))
        }
        return 4 + 22 * levels[index]
    }
}

private struct CallBarButton: View {
    let systemImage: String
    let label: String
    let active: Bool
    var tint: Color? = nil
    var ink: Color? = nil
    let action: () -> Void

    #if os(macOS)
        private static let size: CGFloat = 44
    #else
        private static let size: CGFloat = 40
    #endif

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ink ?? (active ? Theme.pane : Theme.ink))
                .frame(width: Self.size, height: Self.size)
                .background(tint ?? (active ? Theme.ink : Theme.selection), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
    }
}

/// The engine, and for on-device calls voice, speed and language; kept between calls.
private struct CallSettingsPanel: View {
    /// The call runs on GPT-Live, whose voice is set on the gateway.
    let live: Bool
    let liveStatus: VoiceLiveStatus?
    let languageChanged: () -> Void
    let engineChanged: () -> Void
    @AppStorage(CallSettings.engineKey) private var engine = ""
    @AppStorage(CallSettings.voiceKey) private var voice = ""
    @AppStorage(CallSettings.speedKey) private var speed = 1.0
    @AppStorage(CallSettings.languageKey) private var language = ""

    var body: some View {
        VStack(spacing: 4) {
            row("Engine") {
                Picker("Engine", selection: $engine) {
                    Text("Automatic").tag("")
                    Text("On-device").tag("apple")
                    Text("GPT-Live").tag("gpt-live")
                }
            }
            if live {
                HStack {
                    Text("Voice")
                        .font(.system(size: 14.5))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(liveStatus.map { "\($0.voice) · \($0.model)" } ?? "")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryInk)
                }
                .frame(minHeight: 40)
                Text("GPT-Live's voice is set on the gateway. OpenAI bills the call's minutes.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            } else {
                appleRows
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .onChange(of: language) {
            voice = ""
            languageChanged()
        }
        .onChange(of: engine) { engineChanged() }
    }

    @ViewBuilder private var appleRows: some View {
        row("Voice") {
            Picker("Voice", selection: $voice) {
                Text("Best available").tag("")
                ForEach(CallSettings.voices(for: CallSettings.language), id: \.identifier) { voice in
                    Text(voice.name).tag(voice.identifier)
                }
            }
        }
        row("Speed") {
            Picker("Speed", selection: $speed) {
                ForEach(CallSettings.speeds, id: \.self) { speed in
                    Text(speed.formatted(.number.precision(.fractionLength(0...2))) + "×").tag(speed)
                }
            }
        }
        row("Language") {
            Picker("Language", selection: $language) {
                Text("Automatic").tag("")
                ForEach(CallSettings.languages, id: \.identifier) { locale in
                    Text(CallSettings.name(of: locale)).tag(locale.identifier)
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder picker: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.ink)
            Spacer()
            picker()
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
        }
        .frame(minHeight: 40)
    }
}

/// What was said in this call, newest at the bottom, with your words still being recognised.
private struct TranscriptPanel: View {
    let call: any CallEngine
    let agentName: String

    var body: some View {
        Group {
            if call.transcript.isEmpty, call.heard.isEmpty {
                Text("No speech transcribed yet")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(call.transcript) { line in
                            row(line.fromYou ? String(localized: "You") : agentName, line.text)
                        }
                        if !call.heard.isEmpty {
                            row(String(localized: "You"), call.heard).opacity(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: 220)
            }
        }
    }

    private func row(_ who: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(who)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryInk)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
