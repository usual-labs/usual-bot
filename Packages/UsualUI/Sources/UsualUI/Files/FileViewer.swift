import HermesKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// The files the viewer shows. Anything else in a chat stays a file to share.
enum FileKind: Hashable {
    case image, pdf, markdown

    init?(path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        if MediaLoading.imageExtensions.contains(ext) {
            self = .image
        } else if ext == "pdf" {
            self = .pdf
        } else if ext == "md" || ext == "markdown" {
            self = .markdown
        } else {
            return nil
        }
    }

    var symbol: String {
        switch self {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .markdown: "doc.text"
        }
    }
}

/// A file named in a chat or room, open in the viewer.
struct ViewedFile: Hashable {
    let source: MediaSource
    let name: String
    /// Whose files a gateway path names: the chat's Bot, or a room reply's author.
    let profile: String?
    let kind: FileKind
    /// The bytes when this device has them already, such as an image it sent. Not part of what
    /// the file is: with or without them, it's the same file.
    var data: Data? = nil

    static func == (lhs: ViewedFile, rhs: ViewedFile) -> Bool {
        lhs.source == rhs.source && lhs.name == rhs.name && lhs.profile == rhs.profile && lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(source)
        hasher.combine(profile)
    }
}

extension ViewedFile {
    /// The file the ⌥Space panel asked for, when it's for `contactID` and the viewer shows its kind.
    /// From the web the viewer only gets Markdown images, whose addresses may have no extension.
    init?(_ request: FileRequest?, for contactID: Contact.ID) {
        guard let request, request.contactID == contactID else { return nil }
        let kind: FileKind?
        switch request.source {
        case .gateway(let path): kind = FileKind(path: path)
        case .web(let url): kind = FileKind(path: url.path) ?? .image
        }
        guard let kind else { return nil }
        self.init(source: request.source, name: request.name, profile: request.profile, kind: kind)
    }
}

/// An image, a PDF or a Markdown document from a chat, with Share, and Save on the Mac. Beside the
/// conversation on the Mac, pushed on iPhone (`fileViewer`).
struct FileViewer: View {
    let file: ViewedFile

    /// The panel's width on the Mac until you drag it: a profile's, so a window at its usual size
    /// leaves the chat room for your bubbles and their action bar (see known issues).
    static let width: CGFloat = ProfilePanel.width

    @Environment(\.media) private var store
    @State private var phase = Phase.loading
    /// A copy on this device, for Share and Save.
    @State private var copy: URL?
    @State private var attempt = 0
    #if os(macOS)
        @State private var saving = false
        @State private var saved = Data()
        @Zoomed private var iconSize = SidePanelIcon.size
    #endif

    private enum Phase {
        case loading
        case image(Image)
        case pdf(PDFDocument)
        case markdown(String)
        case failed(String)
    }

    private struct LoadKey: Hashable {
        let file: ViewedFile
        let attempt: Int
    }

    var body: some View {
        page
            .task(id: LoadKey(file: file, attempt: attempt)) { await load() }
            // Files a document names open as they would outside the viewer, not over it.
            .environment(\.openFile, nil)
            .environment(\.mediaProfile, file.profile)
    }

    #if os(macOS)
        private var page: some View {
            VStack(spacing: 0) {
                header
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Level with the window buttons, as the panel's close button is.
            .ignoresSafeArea(.container, edges: .top)
            .overlay(alignment: .topTrailing) { actions }
            .fileExporter(
                isPresented: $saving, item: saved,
                contentTypes: [UTType(filenameExtension: (file.name as NSString).pathExtension) ?? .data],
                defaultFilename: file.name
            ) { _ in }
        }

        /// The file's name, in the panel's top row.
        private var header: some View {
            HStack(spacing: 8) {
                Image(systemName: file.kind.symbol)
                    .scaledFont(size: 14)
                    .foregroundStyle(Theme.secondaryInk)
                Text(file.name)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.name)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .zoomedFrame(height: ThreadPane.barItemHeight)
            .padding(.top, ThreadPane.barEdgeMargin)
            .padding(.bottom, 6)
            .padding(.leading, 18)
            // Room for Share, Save and the panel's close button.
            .padding(.trailing, 8 + 3 * (iconSize + 8))
        }

        /// Share and Save, before the panel's close button.
        @ViewBuilder private var actions: some View {
            if let copy {
                HStack(spacing: 8) {
                    ShareLink(item: copy) { SidePanelIcon(systemName: "square.and.arrow.up") }
                        .buttonStyle(.clickable)
                        .help("Share \(file.name)")
                        .accessibilityLabel(Text("Share \(file.name)"))
                    Button {
                        guard let data = try? Data(contentsOf: copy) else { return }
                        saved = data
                        saving = true
                    } label: {
                        SidePanelIcon(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.clickable)
                    .help("Save \(file.name)…")
                    .accessibilityLabel(Text("Save \(file.name)…"))
                }
                .sidePanelTopRow(beforeClose: true)
            }
        }
    #else
        private var page: some View {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.pane)
                .navigationTitle(file.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let copy {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: copy) { Label("Share", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
        }
    #endif

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            ProgressView().controlSize(.small)
        case .image(let image):
            image.resizable().scaledToFit()
                .padding(16)
                .accessibilityLabel(Text("Image \(file.name)"))
        case .pdf(let document):
            PDFDocumentView(document: document)
        case .markdown(let text):
            ScrollView {
                MarkdownView(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .thinScroller()
        case .failed(let reason):
            VStack(spacing: 10) {
                Text(reason).multilineTextAlignment(.center)
                Button("Try Again") { attempt += 1 }
                    .buttonStyle(.clickable(.bordered))
            }
            .scaledFont(size: 13)
            .foregroundStyle(Theme.secondaryInk)
            .padding(.horizontal, 32)
        }
    }

    private func load() async {
        phase = .loading
        copy = nil
        do {
            switch file.kind {
            case .pdf:
                let url = try await localCopy()
                copy = url
                guard let document = PDFDocument(url: url) else {
                    phase = .failed(String(localized: "This isn't a PDF Usual Bot can open. You can still share it."))
                    return
                }
                guard !document.isLocked else {
                    phase = .failed(
                        String(localized: "This PDF is locked with a password. Share it to open it in another app."))
                    return
                }
                phase = .pdf(document)
            case .image:
                let data = try await bytes()
                copy = MediaLoading.temporaryFile(data, name: file.name)
                guard let image = await MediaLoading.image(data, maxPixels: 4096) else {
                    phase = .failed(String(localized: "This isn't an image Usual Bot can show."))
                    return
                }
                phase = .image(image)
            case .markdown:
                let data = try await bytes()
                copy = MediaLoading.temporaryFile(data, name: file.name)
                phase = .markdown(String(decoding: data, as: UTF8.self))
            }
        } catch is CancellationError {
            // Another file took its place.
        } catch {
            phase = .failed(AppModel.describe(error))
        }
    }

    private func bytes() async throws -> Data {
        if let data = file.data { return data }
        return try await MediaLoading.data(file.source, store: store, profile: file.profile)
    }

    /// A PDF comes down whole, past the 16 MB the gateway's data URLs carry (`MediaStore.localFile`).
    private func localCopy() async throws -> URL {
        if case .gateway(let path) = file.source, file.data == nil {
            guard let store, let profile = file.profile else { throw GatewayError.disconnected }
            return try await store.localFile(at: path, profile: profile)
        }
        guard let url = MediaLoading.temporaryFile(try await bytes(), name: file.name) else {
            throw GatewayError.invalidResponse
        }
        return url
    }
}

/// PDFKit's own view: pages in a scrolling column, fitted to the width, with selection, search
/// (⌘F on the Mac) and VoiceOver.
#if os(macOS)
    private struct PDFDocumentView: NSViewRepresentable {
        let document: PDFDocument

        func makeNSView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.backgroundColor = NSColor(Theme.window)
            view.document = document
            return view
        }

        func updateNSView(_ view: PDFView, context: Context) {
            if view.document !== document { view.document = document }
        }
    }
#else
    private struct PDFDocumentView: UIViewRepresentable {
        let document: PDFDocument

        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.backgroundColor = UIColor(Theme.pane)
            view.document = document
            return view
        }

        func updateUIView(_ view: PDFView, context: Context) {
            if view.document !== document { view.document = document }
        }
    }
#endif
