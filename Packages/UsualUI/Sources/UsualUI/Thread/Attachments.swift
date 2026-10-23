import HermesKit
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// What a message box needs to send files with a message. Rooms have none: they take text only.
struct AttachmentSending {
    @Binding var attachments: [Attachment]
    /// Between turns and not already uploading.
    let canSend: Bool
    let isUploading: Bool
    let send: (String, [Attachment]) async -> Bool
}

// MARK: - Reading files

enum AttachmentLoader {
    /// Reads a file the user picked or dropped. Off the main thread: files can be large.
    static func load(_ url: URL) async -> Attachment? {
        await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return make(name: url.lastPathComponent, data: data)
        }.value
    }

    /// The gateway takes PNG, JPEG, GIF, WebP and BMP as images. Photos (HEIC) and TIFFs are
    /// converted to JPEG, so the agent sees them instead of getting a file it can't open.
    static func make(name: String, data: Data) -> Attachment {
        let ext = (name as NSString).pathExtension.lowercased()
        guard ["heic", "heif", "tif", "tiff"].contains(ext), let jpeg = jpeg(from: data) else {
            return Attachment(name: name, data: data)
        }
        return Attachment(name: ((name as NSString).deletingPathExtension) + ".jpg", data: jpeg)
    }

    /// Re-encodes an image as JPEG, keeping its orientation and metadata.
    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImageFromSource(
            destination, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// Files dropped or pasted: Finder and Files hand over URLs; browsers and Photos often only
    /// image data. On the main actor, where the providers come from; the loading itself runs in
    /// the providers' own callbacks.
    @MainActor static func load(_ providers: [NSItemProvider]) async -> [Attachment] {
        var attachments: [Attachment] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                let url = await fileURL(from: provider), let attachment = await load(url)
            {
                attachments.append(attachment)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                let data = await imageData(from: provider)
            {
                let ext = provider.registeredContentTypes.first { $0.conforms(to: .image) }?.preferredFilenameExtension
                attachments.append(make(name: (provider.suggestedName ?? "Image") + "." + (ext ?? "png"), data: data))
            }
        }
        return attachments
    }

    @MainActor private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    @MainActor private static func imageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .image) { data, _ in continuation.resume(returning: data) }
        }
    }
}

// MARK: - Picking files

/// The + at the start of the message box. On the Mac it opens a file picker; on iPhone it offers
/// Photos, the camera and Files.
struct AttachButton: View {
    let add: ([Attachment]) -> Void

    @State private var choosingFiles = false
    #if os(iOS)
        @State private var choosingPhotos = false
        @State private var photos: [PhotosPickerItem] = []
        @State private var takingPhoto = false
    #endif

    var body: some View {
        picker
            .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) {
                result in
                guard case .success(let urls) = result else { return }
                Task {
                    var picked: [Attachment] = []
                    for url in urls {
                        if let attachment = await AttachmentLoader.load(url) { picked.append(attachment) }
                    }
                    add(picked)
                }
            }
    }

    #if os(macOS)
        private var picker: some View {
            Button {
                choosingFiles = true
            } label: {
                icon
            }
            .buttonStyle(.plain)
            .help("Attach Files")
            .accessibilityLabel(Text("Attach Files"))
        }
    #else
        private var picker: some View {
            Menu {
                Button("Photo Library", systemImage: "photo.on.rectangle") { choosingPhotos = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo", systemImage: "camera") { takingPhoto = true }
                }
                Button("Choose File", systemImage: "folder") { choosingFiles = true }
            } label: {
                icon
            }
            .accessibilityLabel(Text("Attach"))
            .photosPicker(isPresented: $choosingPhotos, selection: $photos, maxSelectionCount: 10, matching: .images)
            .onChange(of: photos) { _, items in
                guard !items.isEmpty else { return }
                photos = []
                Task { add(await Self.load(items)) }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { data in add([AttachmentLoader.make(name: "Photo.jpg", data: data)]) }
                    .ignoresSafeArea()
            }
        }

        private static func load(_ items: [PhotosPickerItem]) async -> [Attachment] {
            var attachments: [Attachment] = []
            for (index, item) in items.enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                attachments.append(AttachmentLoader.make(name: "Photo \(index + 1).\(ext)", data: data))
            }
            return attachments
        }
    #endif

    private var icon: some View {
        // A grey circle the size of Send, as in the mockups.
        Image(systemName: "plus")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 28, height: 28)
            .background(Theme.selection, in: Circle())
            .contentShape(Circle())
    }
}

#if os(iOS)
    /// The system camera, returning the photo as JPEG.
    private struct CameraPicker: UIViewControllerRepresentable {
        let take: (Data) -> Void
        @Environment(\.dismiss) private var dismiss

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let parent: CameraPicker
            init(_ parent: CameraPicker) { self.parent = parent }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) {
                    parent.take(data)
                }
                parent.dismiss()
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        }
    }
#endif

// MARK: - Showing attachments

/// Attachments waiting in the message box, each with a button to remove it.
struct AttachmentChips: View {
    @Binding var attachments: [Attachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentTile(kind: attachment.kind, name: attachment.name, imageData: attachment.data)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.primaryInk)
                                    .frame(width: 18, height: 18)
                                    .background(Theme.primary, in: Circle())
                                    .padding(4)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove \(attachment.name)"))
                        }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
    }
}

/// One attachment: an image as a thumbnail, anything else as a named file.
struct AttachmentTile: View {
    let kind: Attachment.Kind
    let name: String
    /// The image's bytes when this device has them; without them an image shows by name.
    var imageData: Data?

    @State private var thumbnail: Image?

    var body: some View {
        Group {
            if kind == .image, imageData != nil {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.selection)
                    thumbnail?.resizable().scaledToFill()
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .task(id: imageData) { thumbnail = imageData.flatMap { Self.thumbnail(of: $0) } }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: kind == .image ? "photo" : "doc")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryInk)
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        // As wide as the name, up to a limit; longer names shorten in the middle.
                        .frame(maxWidth: 180, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Theme.selection, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind == .image ? "Image \(name)" : "File \(name)"))
    }

    /// A small decoded copy, so a 12-megapixel photo doesn't sit in memory at full size.
    static func thumbnail(of data: Data) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 400,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return nil }
        return Image(decorative: image, scale: 1)
    }
}

extension EnvironmentValues {
    /// Images this device sent, by their path on the gateway (`ChatThread.sentImages`).
    @Entry var sentImages: [String: Data] = [:]
}
