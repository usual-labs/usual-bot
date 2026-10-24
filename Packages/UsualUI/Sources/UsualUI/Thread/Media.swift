import HermesKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    /// Reads files agents name in chats from the gateway; set by the signed-in window.
    @Entry var media: MediaStore?
    /// GPT-Live sessions for voice calls; set by the app.
    @Entry var voiceLive: VoiceLiveService?
    /// The profile whose files a message names: the chat's agent, or a room reply's author.
    @Entry var mediaProfile: String?
}

/// Where an image in a chat comes from.
enum MediaSource: Equatable, Hashable {
    /// A path on the gateway, read as the message's profile.
    case gateway(String)
    case web(URL)
}

enum MediaLoading {
    /// Image types that draw inline; anything else is a file to save.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "tif", "tiff"]

    static func isImage(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    @MainActor static func data(
        _ source: MediaSource, store: MediaStore?, profile: String?
    ) async throws -> Data {
        switch source {
        case .gateway(let path):
            guard let store, let profile else { throw GatewayError.disconnected }
            return try await store.file(at: path, profile: profile)
        case .web(let url):
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                throw GatewayError.invalidResponse
            }
            return data
        }
    }

    /// A decoded copy no larger than `maxPixels` on its long side, the right way up.
    static func image(_ data: Data, maxPixels: Int) -> Image? {
        decoded(data, maxPixels: maxPixels)?.image
    }

    /// The decoded copy and its size in pixels.
    static func decoded(_ data: Data, maxPixels: Int) -> (image: Image, pixels: CGSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return nil }
        return (Image(decorative: image, scale: 1), CGSize(width: image.width, height: image.height))
    }

    /// How big an image shows in a reply: its own shape, at most `limit`, and no bigger than its
    /// pixels at 2× (so a small icon stays small).
    static func displaySize(pixels: CGSize, limit: CGSize) -> CGSize {
        guard pixels.width > 0, pixels.height > 0 else { return limit }
        let scale = min(limit.width / pixels.width, limit.height / pixels.height, 0.5)
        return CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
    }

    /// Writes the bytes to a temporary file named `name`, for Share and Save.
    static func temporaryFile(_ data: Data, name: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "UsualBot-media", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name.isEmpty ? "image" : name)
        return (try? data.write(to: url)) != nil ? url : nil
    }
}

/// A `MEDIA:` file in a reply: an image inline, anything else as a file you can save.
struct MediaView: View {
    let path: String

    var body: some View {
        if MediaLoading.isImage(path) {
            ReplyImage(source: .gateway(path), name: (path as NSString).lastPathComponent)
        } else {
            MediaFile(path: path)
        }
    }
}

/// An image in a reply: loads, shows inline, and opens full size on tap.
struct ReplyImage: View {
    let source: MediaSource
    let name: String

    @Environment(\.media) private var store
    @Environment(\.mediaProfile) private var profile
    @State private var phase = Phase.loading
    @State private var viewing = false

    enum Phase {
        case loading
        case loaded(Data, Image, CGSize)
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.selection)
                    .frame(width: 280, height: 180)
                    .overlay { ProgressView().controlSize(.small) }
            case .loaded(_, let image, let pixels):
                // Sized to the image's own shape, so the rounded border hugs it, and narrower on a
                // screen too narrow for that size.
                let size = MediaLoading.displaySize(pixels: pixels, limit: CGSize(width: 420, height: 360))
                Button {
                    viewing = true
                } label: {
                    image.resizable()
                        .aspectRatio(size, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
                        .frame(maxWidth: size.width)
                }
                .buttonStyle(.plain)
                .help("Open \(name)")
            case .failed(let reason):
                AttachmentTile(kind: .image, name: name)
                    .help(reason)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text("Image \(name)"))
        .task(id: source) { await load() }
        .sheet(isPresented: $viewing) {
            if case .loaded(let data, _, _) = phase { MediaViewer(data: data, name: name) }
        }
    }

    private func load() async {
        do {
            let data = try await MediaLoading.data(source, store: store, profile: profile)
            guard let decoded = MediaLoading.decoded(data, maxPixels: 1400) else {
                phase = .failed(String(localized: "This isn't an image Usual Bot can show."))
                return
            }
            phase = .loaded(data, decoded.image, decoded.pixels)
        } catch {
            phase = .failed(AppModel.describe(error))
        }
    }
}

/// A non-image file in a reply: its name, and a way to save it.
struct MediaFile: View {
    let path: String

    @Environment(\.media) private var store
    @Environment(\.mediaProfile) private var profile
    @State private var file: URL?
    @State private var problem: String?

    private var name: String { (path as NSString).lastPathComponent }

    var body: some View {
        HStack(spacing: 8) {
            AttachmentTile(kind: .file, name: name)
            if let file {
                ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryInk)
                    .help("Share \(name)")
            } else {
                Button("Get File", systemImage: "arrow.down.circle") { Task { await fetch() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryInk)
                    .help(problem ?? String(localized: "Get \(name) from the gateway"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fetch() async {
        do {
            let data = try await MediaLoading.data(.gateway(path), store: store, profile: profile)
            file = MediaLoading.temporaryFile(data, name: name)
        } catch {
            problem = AppModel.describe(error)
        }
    }
}

/// An image full size, with Share, and Save on the Mac.
struct MediaViewer: View {
    let data: Data
    let name: String

    @Environment(\.dismiss) private var dismiss
    @State private var image: Image?
    @State private var file: URL?
    #if os(macOS)
        @State private var saving = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let file {
                    ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                        .help("Share")
                }
                #if os(macOS)
                    Button("Save…") { saving = true }
                #endif
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            ZStack {
                if let image {
                    image.resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding([.horizontal, .bottom], 18)
        }
        #if os(macOS)
            .frame(minWidth: 520, idealWidth: 900, minHeight: 420, idealHeight: 700)
            .fileExporter(
                isPresented: $saving, item: data,
                contentTypes: [UTType(filenameExtension: (name as NSString).pathExtension) ?? .data],
                defaultFilename: name
            ) { _ in }
        #endif
        .background(Theme.pane)
        .task {
            image = MediaLoading.image(data, maxPixels: 4096)
            file = MediaLoading.temporaryFile(data, name: name)
        }
    }
}
