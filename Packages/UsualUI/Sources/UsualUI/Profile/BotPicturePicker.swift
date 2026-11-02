import HermesKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import PhotosUI
#endif

extension View {
    /// Asks for a picture for a Bot: an open panel on the Mac, Photos or Files on iPhone. `picked`
    /// gets the file as it is; `AppModel` crops and scales it.
    func botPicturePicker(isPresented: Binding<Bool>, picked: @escaping (Data) -> Void) -> some View {
        modifier(BotPicturePicker(isPresented: isPresented, picked: picked))
    }

    /// On the Mac, a picture dropped here goes to `picked`. Nothing on iPhone.
    func botPictureDrop(isTargeted: Binding<Bool>, enabled: Bool = true, picked: @escaping (Data) -> Void)
        -> some View
    {
        #if os(macOS)
            onDrop(of: [.fileURL, .image], isTargeted: isTargeted) { providers in
                guard enabled else { return false }
                Task {
                    if let data = await AttachmentLoader.load(providers).first?.data { picked(data) }
                }
                return true
            }
        #else
            self
        #endif
    }
}

private struct BotPicturePicker: ViewModifier {
    @Binding var isPresented: Bool
    let picked: (Data) -> Void

    #if os(iOS)
        @State private var choosingPhoto = false
        @State private var choosingFile = false
        @State private var photo: PhotosPickerItem?
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
            content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.image]) { result in
                load(result)
            }
        #else
            content
                .confirmationDialog("Choose a Picture", isPresented: $isPresented, titleVisibility: .visible) {
                    Button("Photo Library") { choosingPhoto = true }
                    Button("Files") { choosingFile = true }
                    Button("Cancel", role: .cancel) {}
                }
                .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
                .onChange(of: photo) { _, item in
                    guard let item else { return }
                    photo = nil
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) { picked(data) }
                    }
                }
                .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
                    load(result)
                }
        #endif
    }

    private func load(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        Task {
            if let data = await AttachmentLoader.load(url)?.data { picked(data) }
        }
    }
}
