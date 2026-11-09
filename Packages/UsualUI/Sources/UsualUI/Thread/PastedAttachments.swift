#if os(macOS)
    import AppKit
    import HermesKit
    import SwiftUI
    import UniformTypeIdentifiers

    /// What ⌘V attaches from the clipboard.
    enum PastedAttachments {
        enum Item: Equatable {
            /// Files copied in Finder.
            case files([URL])
            /// An image copied on its own: a screenshot, or Copy Image in a browser or Preview.
            case image(Data, UTType)
        }

        /// Image types in the order they're taken; TIFF last, since it's what everything also offers.
        static let imageTypes: [UTType] = [.png, .jpeg, .heic, .gif, .webP, .bmp, .tiff]

        /// Copied files, else an image copied without text. Text wins over an image: Numbers, Excel
        /// and Word copy a picture of the text beside it, and that should paste as text.
        static func item(on pasteboard: NSPasteboard) -> Item? {
            if let urls = pasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
            {
                return .files(urls)
            }
            guard pasteboard.availableType(from: [.string]) == nil else { return nil }
            for type in imageTypes {
                if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type.identifier)) {
                    return .image(data, type)
                }
            }
            return nil
        }

        /// ⌘V, with no other modifier: ⇧⌥⌘V pastes text without its style.
        nonisolated static func isPaste(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard modifiers == .command else { return false }
            // Layouts that type other letters keep ⌘V on the key where QWERTY has V.
            guard let key = event.charactersIgnoringModifiers?.lowercased(), key.allSatisfy(\.isASCII) else {
                return event.keyCode == 9
            }
            return key == "v"
        }

        static func load(_ item: Item) async -> [Attachment] {
            switch item {
            case .files(let urls):
                var attachments: [Attachment] = []
                for url in urls {
                    if let attachment = await AttachmentLoader.load(url) { attachments.append(attachment) }
                }
                return attachments
            case .image(let data, let type):
                return [AttachmentLoader.make(name: "Image." + (type.preferredFilenameExtension ?? "png"), data: data)]
            }
        }
    }

    extension View {
        /// Mac: ⌘V in this window attaches copied files and images, while the message box has focus
        /// or nothing else takes typing; text pastes as usual. The field's editor takes ⌘V before
        /// SwiftUI's `onPasteCommand` sees it, and pastes a copied file as its name, so this watches
        /// the key itself. Edit ▸ Paste in the menu bar still goes to the field.
        func pastesAttachments(enabled: Bool, focused: Bool, add: @escaping ([Attachment]) -> Void) -> some View {
            background(
                PasteMonitor(enabled: enabled, focused: focused, add: add)
                    .frame(width: 0, height: 0).accessibilityHidden(true))
        }
    }

    private struct PasteMonitor: NSViewRepresentable {
        let enabled: Bool
        let focused: Bool
        let add: ([Attachment]) -> Void

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.view = view
            updateNSView(view, context: context)
            context.coordinator.start()
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            context.coordinator.enabled = enabled
            context.coordinator.focused = focused
            context.coordinator.add = add
        }

        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
            coordinator.stop()
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        @MainActor final class Coordinator {
            weak var view: NSView?
            var enabled = true
            var focused = false
            var add: ([Attachment]) -> Void = { _ in }
            private var monitor: Any?

            func start() {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let handled = MainActor.assumeIsolated { self?.paste(event) ?? false }
                    return handled ? nil : event
                }
            }

            func stop() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }

            private func paste(_ event: NSEvent) -> Bool {
                guard enabled, let window = view?.window, event.window === window, PastedAttachments.isPaste(event),
                    focused || !TypingFocus.Coordinator.takesKeys(window.firstResponder),
                    let item = PastedAttachments.item(on: .general)
                else { return false }
                let add = add
                Task { add(await PastedAttachments.load(item)) }
                return true
            }
        }
    }
#endif

#if os(iOS)
    import CoreTransferable
    import HermesKit
    import SwiftUI
    import UniformTypeIdentifiers

    /// iPhone: Paste attaches a copied photo or file the text field can't paste itself. Before
    /// iOS 27 SwiftUI has no paste destination, and `onPasteCommand` is Mac-only.
    struct PastesAttachmentsOnPhone: ViewModifier {
        let enabled: Bool
        let add: ([Attachment]) -> Void

        func body(content: Content) -> some View {
            if #available(iOS 27, *), enabled {
                content.pasteDestination(for: PastedFile.self) { files in add(files.map(\.attachment)) }
            } else {
                content
            }
        }
    }

    /// A copied photo or file, never text: text is the field's to paste.
    struct PastedFile: Transferable {
        let attachment: Attachment

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .data) { received in
                let url = received.file
                if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .text) {
                    throw CocoaError(.fileReadUnsupportedScheme)
                }
                let data = try Data(contentsOf: url)
                return PastedFile(attachment: AttachmentLoader.make(name: url.lastPathComponent, data: data))
            }
        }
    }
#endif
