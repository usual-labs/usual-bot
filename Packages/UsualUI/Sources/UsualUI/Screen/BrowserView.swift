import HermesKit
import SwiftUI

/// An agent's browser, live and watch only: the tab it has open along the top, the page below,
/// scaled to fit. A Mac window of its own; a full-screen cover on iPhone, where you pinch to zoom.
struct BrowserView: View {
    let contact: Contact
    let browser: BotBrowser
    /// The agent's chat, to say when it's browsing.
    let thread: ChatThread?
    var close: (() -> Void)? = nil

    @Environment(\.gatewayOnline) private var isOnline
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
            stage
        }
        .background(Theme.window)
        .task(id: contact.id) {
            if browser.connection == .idle { browser.connect() }
        }
        .onDisappear { browser.disconnect() }
        // iOS cuts the socket in the background; come back to a live page.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, case .failed = browser.connection { browser.connect() }
        }
        // The gateway is back: pick the page up again.
        .onChange(of: isOnline) { _, online in
            if online, case .failed = browser.connection { browser.connect() }
        }
    }

    // MARK: - Bar

    private var bar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let close {
                    Button("Close", systemImage: "xmark", action: close)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.clickable(.borderless))
                        .frame(width: 32, height: 32)
                }
                pill
                if let page = browser.page, browser.connection == .live { tab(page) }
                Spacer(minLength: 0)
            }
            if !isOnline {
                Text("Offline. The page may be out of date until the gateway is back.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pill: some View {
        let browsing = thread?.state.isUsingBrowser == true
        let (text, tint): (LocalizedStringKey, Color) =
            switch browser.connection {
            case .live: browsing ? ("\(contact.name) is browsing", Theme.online) : ("Watching", Theme.secondaryInk)
            case .waiting: ("Browser closed", Theme.secondaryInk)
            default: ("Not connected", Theme.secondaryInk)
            }
        return HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(text).scaledFont(size: 13, weight: .medium).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.selection, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    /// The open tab: its title, and where it is.
    private func tab(_ page: BotBrowser.Page) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title = page.title, !title.isEmpty {
                Text(verbatim: title).scaledFont(size: 13, weight: .medium).foregroundStyle(Theme.ink)
            }
            if let url = page.url, !url.isEmpty {
                Text(verbatim: url).scaledFont(size: 12).foregroundStyle(Theme.secondaryInk)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Open tab"))
        .accessibilityValue(Text(verbatim: [page.title, page.url].compactMap { $0 }.joined(separator: ", ")))
    }

    // MARK: - Page

    private var stage: some View {
        ZStack {
            Color.black
            if let frame = browser.frame {
                BrowserCanvas(frame: frame, name: contact.name)
                    .opacity(browser.connection == .live ? 1 : 0.4)
            }
            overlay
        }
    }

    @ViewBuilder private var overlay: some View {
        switch browser.connection {
        case .connecting:
            label {
                ProgressView().controlSize(.small).tint(.white)
            } text: {
                Text("Connecting to the browser…")
            }
        case .waiting:
            VStack(spacing: 6) {
                Text("\(contact.name)'s browser isn't open").scaledFont(size: 15, weight: .semibold)
                Text("It opens when \(contact.name) browses the web, and shows here as it does.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(20)
            .glassEffect(.regular.tint(.black.opacity(0.4)), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
        case .live where browser.frame == nil:
            label {
                ProgressView().controlSize(.small).tint(.white)
            } text: {
                Text("Loading the page…")
            }
        case .failed(let reason):
            VStack(spacing: 10) {
                Text(reason).multilineTextAlignment(.center)
                Button("Try Again") { browser.connect() }
                    .buttonStyle(.inkGlassProminent)
                    .disabled(!isOnline)
            }
            .padding(20)
            .glassEffect(.regular.tint(.black.opacity(0.4)), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .scaledFont(size: 13)
        case .idle:
            Button("Watch") { browser.connect() }.buttonStyle(.inkGlassProminent).disabled(!isOnline)
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
        .glassEffect(.regular.tint(.black.opacity(0.4)), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

#if os(iOS)
    /// The page, scaled to fit; pinch to zoom in on it, and drag to move around.
    private struct BrowserCanvas: UIViewRepresentable {
        let frame: CGImage
        let name: String

        func makeUIView(context: Context) -> CanvasScrollView {
            CanvasScrollView(
                label: String(localized: "\(name)'s browser"),
                hint: String(localized: "Pinch to zoom in on the page."))
        }

        func updateUIView(_ view: CanvasScrollView, context: Context) {
            view.show(frame)
        }
    }
#else
    /// The page, scaled to fit the window. The window grows to show it at full size.
    private struct BrowserCanvas: View {
        let frame: CGImage
        let name: String

        var body: some View {
            Image(decorative: frame, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityRepresentation {
                    Text("\(name)'s browser")
                }
        }
    }
#endif

/// The Mac's window for an agent's browser (`WindowGroup(id: "bot-browser", for: Contact.ID.self)`).
public struct BotBrowserWindow: View {
    let model: AppModel
    let contactID: Contact.ID

    public init(model: AppModel, contactID: Contact.ID) {
        self.model = model
        self.contactID = contactID
    }

    public var body: some View {
        if let contact = model.contacts.first(where: { $0.id == contactID }) {
            BrowserView(contact: contact, browser: model.browser(for: contact), thread: model.thread(for: contact))
                .environment(\.gatewayOnline, model.isOnline)
                .navigationTitle(Text("\(contact.name)'s Browser"))
                .frame(minWidth: 480, minHeight: 360)
        } else {
            Text("This Bot isn't on the gateway anymore.")
                .foregroundStyle(Theme.secondaryInk)
                .frame(minWidth: 480, minHeight: 360)
        }
    }
}
