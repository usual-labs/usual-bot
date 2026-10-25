import AVFoundation
import HermesKit
import Observation
import SwiftUI
import WebKit
import os

/// What the call bar shows and controls, whichever engine runs the call.
@MainActor
protocol CallEngine: AnyObject, Observable {
    var thread: ChatThread { get }
    var phase: VoiceCall.Phase { get }
    var transcript: [VoiceCall.Line] { get }
    /// Your words as they're recognised, before they join the transcript.
    var heard: String { get }
    var levels: [Double] { get }
    var muted: Bool { get set }
    func start() async
    func end()
}

extension VoiceCall: CallEngine {}

/// A call through GPT-Live, OpenAI's full-duplex voice model, which hands real work to Hermes: it
/// listens and talks at once (speak over it to cut in), and when you ask for something it
/// delegates; the delegation becomes an ordinary turn in this chat and Hermes's reply is what it
/// says. The media runs in WebKit's WebRTC in a hidden web view (`live-call.html`); the gateway
/// opens the session with its own OpenAI key. OpenAI bills the call's minutes.
@MainActor
@Observable
final class LiveCall: CallEngine {
    private(set) var phase = VoiceCall.Phase.starting
    private(set) var transcript: [VoiceCall.Line] = []
    /// GPT-Live transcribes both sides into the transcript as it goes.
    let heard = ""
    private(set) var levels = [Double](repeating: 0, count: 14)
    var muted = false {
        didSet { run("setMuted(\(muted))") }
    }

    let thread: ChatThread
    /// Kept in the view hierarchy by the call bar: WebKit plays and records only from a web view
    /// that's on screen.
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let bridge = LiveBridge()
    @ObservationIgnored private let service: VoiceLiveService
    @ObservationIgnored private let profile: String
    /// The delegation Hermes is answering.
    @ObservationIgnored private var delegation: Delegation?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var speaking = false

    init(thread: ChatThread, profile: String, service: VoiceLiveService) {
        self.thread = thread
        self.profile = profile
        self.service = service
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
            configuration.allowsInlineMediaPlayback = true
        #endif
        configuration.userContentController.add(bridge, name: "live")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        webView.uiDelegate = bridge
        webView.navigationDelegate = bridge
        bridge.call = self
    }

    func start() async {
        guard phase == .starting else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed(String(localized: "The microphone is off for Usual Bot. Turn it on in Settings › Privacy."))
            return
        }
        #if os(iOS)
            // The agent's voice from the loudspeaker (or headphones), not the earpiece.
            try? AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        guard let url = Bundle.module.url(forResource: "live-call", withExtension: "html"),
            let page = try? String(contentsOf: url, encoding: .utf8)
        else {
            phase = .failed(String(localized: "The call couldn't start."))
            return
        }
        // A secure origin, so WebKit allows the microphone; nothing is loaded from it.
        webView.loadHTMLString(page, baseURL: URL(string: "https://call.usualbot.invalid/"))
    }

    func end() {
        guard phase != .ended else { return }
        if case .failed = phase {} else { phase = .ended }
        watch?.cancel()
        run("close()")
        // The page reports `closed` when the session is gone; drop the bridge after a grace period
        // either way, so the web view and this call can go.
        Task { [webView, bridge] in
            try? await Task.sleep(for: .seconds(16))
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "live")
            bridge.call = nil
        }
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: From the page

    fileprivate func pageLoaded() {
        run("start()")
    }

    fileprivate func received(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "offer":
            guard let sdp = message["sdp"] as? String else { return }
            Task { await exchange(sdp) }
        case "started":
            if phase == .starting { phase = .listening }
        case "level":
            let mic = message["mic"] as? Double ?? 0
            speaking = message["speaking"] as? Bool ?? false
            levels = Array(levels.dropFirst()) + [muted || speaking ? 0 : mic]
            if phase == .listening, speaking {
                phase = .speaking
            } else if phase == .speaking, !speaking {
                phase = delegation == nil ? .listening : .thinking
            }
        case "transcript":
            guard let text = message["text"] as? String, !text.isEmpty else { return }
            let fromYou = message["speaker"] as? String == "user"
            if let last = transcript.last, last.fromYou == fromYou {
                transcript[transcript.count - 1].text += text
            } else {
                transcript.append(VoiceCall.Line(fromYou: fromYou, text: text.trimmingCharacters(in: .whitespaces)))
            }
        case "delegation":
            guard let id = message["id"] as? String else { return }
            delegate(id, prompt: message["prompt"] as? String ?? "", context: message["context"] as? String ?? "")
        case "error":
            Self.log.error("GPT-Live: \(message["message"] as? String ?? "", privacy: .public)")
        case "failed":
            let name = message["name"] as? String ?? ""
            phase = .failed(
                name == "NotAllowedError"
                    ? String(localized: "The microphone is off for Usual Bot. Turn it on in Settings › Privacy.")
                    : String(localized: "The call couldn't start: \(message["message"] as? String ?? "")"))
            run("close()")
        case "closed":
            let reason = message["reason"] as? String ?? ""
            Self.log.notice("GPT-Live closed: \(reason, privacy: .public)")
            watch?.cancel()
            if phase != .ended, reason != "close_requested" {
                phase = .failed(String(localized: "The call ended (\(reason))."))
            }
        default:
            break
        }
    }

    /// The app, not the page, asks the gateway for the session: the page never sees the sign-in.
    private func exchange(_ offer: String) async {
        do {
            let answer = try await service.answer(offer: offer, history: thread.liveHistory(), profile: profile)
            run("answer(\(Self.literal(answer)))")
        } catch {
            phase = .failed(String(localized: "GPT-Live couldn't start: \(AppModel.describe(error))"))
            run("close()")
        }
    }

    // MARK: Delegations

    /// GPT-Live wants Hermes: your last words become a turn in this chat, and the reply is fed
    /// back for the voice to say as it streams.
    private func delegate(_ id: String, prompt: String, context: String) {
        watch?.cancel()
        phase = speaking ? .speaking : .thinking
        Task {
            await thread.delegate(prompt, spokenContext: context)
            // Your words are the last item now; the reply follows them.
            delegation = Delegation(id: id, replyStart: thread.state.items.count)
            watch = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.feedReply() else { return }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    /// One look at the reply: says its new sentences, and tool progress meanwhile. `false` once
    /// the turn is over.
    private func feedReply() -> Bool {
        guard var current = delegation else { return false }
        let running = thread.state.isRunning
        if let tool = currentTool(from: current.replyStart), tool != current.tool {
            current.tool = tool
            run("think(\(Self.literal(current.id)), \(Self.literal("Hermes is working: \(tool). Not done yet.")))")
        }
        // Whole sentences while it streams, the rest when the turn ends; code and file lines stay unsaid.
        let sentences = current.reader.sentences(in: replyText(from: current.replyStart), final: !running)
        if !sentences.isEmpty {
            current.said = true
            run("speak(\(Self.literal(current.id)), \(Self.literal(sentences.joined(separator: " "))))")
        }
        guard !running else {
            delegation = current
            return true
        }
        if !current.said {
            run(
                "think(\(Self.literal(current.id)), \(Self.literal("Hermes finished that request without a spoken result.")))"
            )
        }
        delegation = nil
        if phase == .thinking { phase = .listening }
        return false
    }

    private func replyText(from start: Int) -> String {
        let items = thread.state.items
        var parts: [String] = []
        if start < items.count {
            for item in items[start...] {
                if case .assistant(let text) = item.content { parts.append(text) }
            }
        }
        if !thread.state.draft.isEmpty { parts.append(thread.state.draft) }
        return parts.joined(separator: "\n\n")
    }

    private func currentTool(from start: Int) -> String? {
        let items = thread.state.items
        guard start < items.count, case .activity(let steps) = items.last?.content,
            let step = steps.last(where: { $0.state == .running })
        else { return nil }
        return step.name
    }

    // MARK: To the page

    private func run(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// A Swift string as a JavaScript string literal.
    private static func literal(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text), let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }

    private static let log = Logger(subsystem: "UsualBot", category: "call")
}

/// A request GPT-Live handed to Hermes: where the reply starts in the chat and how much of it
/// the voice has been given.
private struct Delegation {
    let id: String
    let replyStart: Int
    var reader = SpokenReply()
    var said = false
    var tool: String?
}

/// WebKit's delegate for the call page: messages, the microphone and the page load. Weak to the
/// call, so the web view's controller doesn't keep it alive.
private final class LiveBridge: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    weak var call: LiveCall?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { call?.received(body) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { call?.pageLoaded() }
    }

    /// The page may use the microphone (the app already has the person's permission); never the camera.
    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }
}

/// Holds the call's web view in the view hierarchy, where WebKit lets it play and record.
struct LiveCallHost: View {
    let webView: WKWebView

    var body: some View {
        Host(webView: webView).frame(width: 1, height: 1).opacity(0.01).accessibilityHidden(true)
    }

    #if os(macOS)
        private struct Host: NSViewRepresentable {
            let webView: WKWebView
            func makeNSView(context: Context) -> WKWebView { webView }
            func updateNSView(_ view: WKWebView, context: Context) {}
        }
    #else
        private struct Host: UIViewRepresentable {
            let webView: WKWebView
            func makeUIView(context: Context) -> WKWebView { webView }
            func updateUIView(_ view: WKWebView, context: Context) {}
        }
    #endif
}
