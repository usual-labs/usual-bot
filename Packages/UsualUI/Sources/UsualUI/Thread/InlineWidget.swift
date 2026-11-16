import HermesKit
import SwiftUI

extension EnvironmentValues {
    /// Whether widgets run here; where they don't (the ⌥Space panel), they show as a card.
    @Entry var runsWidgets = true
    /// The chat a widget's prompts go to (`window.hermes.send`). Only a Bot Chat's transcript
    /// sets it: elsewhere, rooms included, a widget can't talk back.
    @Entry var widgetChat: ChatThread? = nil
}

/// A `::preview{file="…"}` page in a reply, running live in the message as in Hermes's desktop
/// app. It sizes itself to the page: the height follows it, within `WidgetPage`'s limits, and the
/// width is the page's first measured width.
struct InlineWidget: View {
    let directive: WidgetDirective
    /// The reply is still being written, so the page may be too.
    var isBeingWritten = false

    @Environment(\.media) private var store
    @Environment(\.mediaProfile) private var profile
    @Environment(\.runsWidgets) private var runs
    @Environment(\.gatewayOnline) private var isOnline
    @Environment(\.widgetChat) private var chat
    @Environment(\.messageTextSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    @State private var phase = Phase.loading
    /// Counts Try Again presses, so the load runs again.
    @State private var attempt = 0
    /// On screen now, and whether its page is running: it stops a while after it scrolls away.
    @State private var isVisible = false
    @State private var isRunning = false
    /// The page's own height, before clamping, and its width once measured.
    @State private var pageHeight: CGFloat?
    @State private var pageWidth: CGFloat?
    /// How wide the frame came out, which a page wider than it scrolls across.
    @State private var frameWidth: CGFloat?
    /// When the page last had a prompt let through (`WidgetIntent`), and the tap it used.
    @State private var lastSent: ContinuousClock.Instant?
    @State private var spentTap: ContinuousClock.Instant?
    /// The chat's `turnsEnded` when the page was last read.
    @State private var readAfterTurn: Int?

    enum Phase: Equatable {
        case loading
        case loaded(String)
        /// Not read yet, and the gateway isn't reachable: it loads when it is.
        case offline
        case failed(String)
    }

    /// What the load task does when it runs: on appearing, when the reply finishes, when the
    /// gateway comes back, on Try Again, or when a turn in its chat ends. A page already read
    /// stays: the transcript keeps its views, so this runs once per widget each time a chat opens,
    /// not as it scrolls.
    enum LoadStep: Equatable {
        case load, waitForGateway, keep
    }

    /// `isStale`: a turn in the chat ended since the page was read, and the page is running. Its
    /// agent may have rewritten it (widgets talking back are answered that way); one off screen is
    /// read when it runs again, so a long chat doesn't read every widget after every reply.
    static func loadStep(_ phase: Phase, runs: Bool, isBeingWritten: Bool, isOnline: Bool, isStale: Bool = false)
        -> LoadStep
    {
        guard runs, !isBeingWritten else { return .keep }
        if case .loaded = phase { return isStale && isOnline ? .load : .keep }
        return isOnline ? .load : .waitForGateway
    }

    /// How long a page keeps running off screen, so scrolling past and back keeps its state.
    private static let offscreenGrace = Duration.seconds(20)

    private var name: String { (directive.file as NSString).lastPathComponent }

    var body: some View {
        Group {
            if !runs {
                WidgetCard(
                    name: name, detail: String(localized: "Open the chat in Usual Bot to use this widget."))
            } else if phase == .offline {
                WidgetCard(
                    name: name,
                    detail: String(localized: "Usual Bot isn't connected to the gateway. This widget loads when it is.")
                )
            } else if case .failed(let reason) = phase {
                // A failure while the gateway is reachable may not pass by itself, such as a page
                // the agent hasn't written yet, so it can be tried again.
                WidgetCard(name: name, detail: String(localized: "Couldn't show this widget. \(reason)")) {
                    phase = .loading
                    attempt += 1
                }
            } else {
                frame
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Widget \(name)"))
        // The connection is in the key, so a page that failed or waited while it was down loads
        // when it's back; the chat's turns are too, as its agent may have rewritten the page.
        .task(
            id: LoadKey(
                file: directive.file, profile: profile, isBeingWritten: isBeingWritten, isOnline: isOnline,
                attempt: attempt, turn: chat?.turnsEnded, isRunning: isRunning)
        ) {
            let turn = chat?.turnsEnded
            switch Self.loadStep(
                phase, runs: runs, isBeingWritten: isBeingWritten, isOnline: isOnline,
                isStale: isRunning && readAfterTurn != turn)
            {
            case .load:
                readAfterTurn = turn
                await load()
            case .waitForGateway: phase = .offline
            case .keep: break
            }
        }
    }

    private var height: CGFloat {
        pageHeight.map(WidgetPage.clamped) ?? WidgetPage.startHeight(directive.height)
    }

    @ViewBuilder private var frame: some View {
        Group {
            if case .loaded(let html) = phase, isRunning {
                WidgetFrame(html: html, theme: theme, scrolls: scrolls, canSend: chat != nil, onMessage: receive)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.ink.opacity(0.04))
                    .overlay {
                        if phase == .loading { ProgressView().controlSize(.small) }
                    }
            }
        }
        .frame(height: height)
        .frame(maxWidth: pageWidth ?? .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { frameWidth = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        .task(id: isVisible) {
            if isVisible {
                isRunning = true
            } else if isRunning {
                // sleep-ok: a page scrolled away keeps running a little, in case you come back.
                try? await Task.sleep(for: Self.offscreenGrace)
                if !Task.isCancelled { isRunning = false }
            }
        }
    }

    /// Taller than the frame can grow, or wider than the message: it scrolls inside, as a page in
    /// Hermes's frame does. Otherwise a swipe over it scrolls the chat.
    private var scrolls: Bool {
        (pageHeight ?? 0) > WidgetPage.maxHeight || (pageWidth ?? 0) > (frameWidth ?? .infinity) + 1
    }

    private func receive(_ message: WidgetMessage) {
        switch message {
        case .size(let height, let width):
            if abs(height - (pageHeight ?? WidgetPage.startHeight(directive.height))) > WidgetPage.tolerance {
                pageHeight = height
            }
            // Taken once: following it would shrink a page whose parts are a share of its width,
            // a little more each time.
            if pageWidth == nil, width > 0 { pageWidth = width }
        case .send(let request):
            guard let chat else {
                request.reply(.undelivered(.room, String(localized: "This widget can't send messages here.")))
                return
            }
            switch WidgetIntent.evaluate(
                request.body, now: .now, tappedAt: request.tappedAt, spentTap: spentTap, lastAccepted: lastSent)
            {
            case .failure(let refusal):
                request.reply(refusal.ack)
            case .success(let prompt):
                lastSent = .now
                spentTap = request.tappedAt
                Task { request.reply(await chat.sendFromWidget(prompt)) }
            }
        }
    }

    private var theme: WidgetPage.Theme {
        func css(_ color: Color) -> String {
            let resolved = color.resolve(in: environment)
            return WidgetPage.css(
                red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue),
                opacity: Double(resolved.opacity))
        }
        return WidgetPage.Theme(
            dark: colorScheme == .dark, foreground: css(Theme.ink), mutedForeground: css(Theme.secondaryInk),
            accent: css(Theme.link), border: css(Theme.border), card: css(Theme.codeFill),
            fontSize: Double(textSize))
    }

    private func load() async {
        do {
            guard let store, let profile else { throw GatewayError.disconnected }
            // Not from the media cache: the agent updates a widget by rewriting its page.
            let data = try await store.file(at: directive.file, profile: profile, fresh: true)
            // The key changed while it read (the connection dropped or came back): the newer load
            // decides.
            guard !Task.isCancelled else { return }
            guard let html = String(data: data, encoding: .utf8) else {
                phase = .failed(String(localized: "\(name) isn't a web page."))
                return
            }
            // The same page keeps running, with its state.
            if phase != .loaded(html) { phase = .loaded(html) }
        } catch {
            guard !Task.isCancelled else { return }
            // A page already showing stays, offline included.
            if case .loaded = phase { return }
            phase = .failed(AppModel.describe(error))
        }
    }

    private struct LoadKey: Equatable {
        let file: String
        let profile: String?
        let isBeingWritten: Bool
        let isOnline: Bool
        let attempt: Int
        let turn: Int?
        let isRunning: Bool
    }
}

/// A widget shown as what it is instead of running: its name, and why.
struct WidgetCard: View {
    let name: String
    let detail: String
    var tryAgain: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).scaledFont(size: 13, weight: .semibold).foregroundStyle(Theme.ink)
                Text(detail).scaledFont(size: 12.5).foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let tryAgain {
                    Button("Try Again", action: tryAgain)
                        .buttonStyle(.clickable(.borderless))
                        .scaledFont(size: 12.5, weight: .medium)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }
}
