import HermesKit
import SwiftUI

extension EnvironmentValues {
    /// Opens a file in the viewer beside the chat or room (`fileViewer`). `nil` where there's no
    /// viewer: an image opens full size in a sheet there, and other files are only shared.
    @Entry var openFile: ((ViewedFile) -> Void)?
}

extension View {
    /// Opens the images, PDFs and Markdown files a chat or room names in the file viewer: beside
    /// the conversation on the Mac, pushed on iPhone. One panel shows at a time, so opening a file
    /// closes `otherPanel` (the profile or room details) and opening that closes the file. Leaving
    /// the chat closes it too. `requested` is a file the ⌥Space panel asked for.
    func fileViewer(
        in chatID: Contact.ID, otherPanel: Binding<Bool>, requested: FileRequest? = nil,
        openedRequested: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            FileViewing(chatID: chatID, otherPanel: otherPanel, requested: requested, openedRequested: openedRequested))
    }
}

private struct FileViewing: ViewModifier {
    let chatID: Contact.ID
    @Binding var otherPanel: Bool
    let requested: FileRequest?
    let openedRequested: () -> Void

    @State private var file: ViewedFile?

    func body(content: Content) -> some View {
        content
            .environment(\.openFile, open)
            // A request can come with the chat it's for, and the order of these two isn't fixed.
            .onChange(of: chatID) {
                file = nil
                openRequested()
            }
            .onChange(of: requested, initial: true) { openRequested() }
            .onChange(of: otherPanel) { _, shown in
                if shown { file = nil }
            }
            #if os(macOS)
                .sidePanel(
                    isPresented: file != nil, widthKey: "fileViewerWidth", idealWidth: FileViewer.width,
                    widthRange: 320...640, closeTitle: "Close File"
                ) {
                    file = nil
                } panel: {
                    if let file { FileViewer(file: file) }
                }
            #else
                .navigationDestination(item: $file) { FileViewer(file: $0) }
            #endif
    }

    private func open(_ wanted: ViewedFile) {
        otherPanel = false
        file = wanted
    }

    private func openRequested() {
        guard let requested, requested.contactID == chatID else { return }
        openedRequested()
        if let wanted = ViewedFile(requested, for: chatID) { open(wanted) }
    }
}
