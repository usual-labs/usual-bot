import SwiftUI

/// Device-local preferences shared with the native app shell.
public enum AppPreferences {
    public static let appearanceKey = "appearance"
    /// iPhone's Chat text size. The Mac zooms the whole window instead (`Zoom`).
    public static let textSizeKey = "chatTextSize"
    public static let commandReturnKey = "commandReturnToSend"
    public static let notificationsKey = "taskNotifications"
    public static let messageNotificationsKey = "messageNotifications"
    public static let needsYouNotificationsKey = "needsYouNotifications"
    public static let notificationSoundKey = "notificationSound"
    public static let notificationPreviewsKey = "notificationPreviews"
    /// Off: an agent's message appears once it's written, not word by word.
    public static let streamRepliesKey = "streamReplies"
    /// Off: chats leave out the lines for tools a Bot used (`TranscriptItem.isToolActivity`).
    public static let showToolActivityKey = "showToolActivity"
}

extension EnvironmentValues {
    @Entry var messageTextSize: CGFloat = Theme.messageSize
    /// The window's zoom, for its sheets: a Mac sheet doesn't inherit the Dynamic Type size that
    /// carries it (`Zoom`), so `SheetForm` sets it again from here.
    @Entry var windowZoom: DynamicTypeSize = .large
}

extension View {
    /// Apply at each window and panel root so preferences update every surface immediately.
    /// `zooms`: the Mac's View ▸ Zoom applies here. Settings, a window of the system's own, doesn't.
    public func appPreferences(zooms: Bool = true) -> some View { modifier(PreferencesStyle(zooms: zooms)) }
}

private struct PreferencesStyle: ViewModifier {
    let zooms: Bool
    @AppStorage(AppPreferences.appearanceKey) private var appearance = "system"
    @AppStorage(AppPreferences.textSizeKey) private var textSize = 0
    #if os(macOS)
        @AppStorage(Zoom.key) private var zoom = Zoom.initialLevel(
            chatTextSize: UserDefaults.standard.integer(forKey: AppPreferences.textSizeKey))
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .environment(\.messageTextSize, Theme.scaled(Theme.messageSize + textAdjustment, for: textSizeCategory))
            #if os(macOS)
                .modifier(MacZoom(size: zooms ? Zoom.size(zoom) : .large))
                .environment(\.windowZoom, zooms ? Zoom.size(zoom) : .large)
            #endif
            // The pointing hand over buttons that pick no style; the rest wrap theirs in
            // `.clickable(_:)`.
            .buttonStyle(.clickable(.automatic))
    }

    /// On iPhone the in-app setting picks the size at the default text size, and Dynamic Type
    /// grows it from there. The Mac's zoom grows it with everything else.
    private var textAdjustment: CGFloat {
        #if os(macOS)
            0
        #else
            CGFloat(min(max(textSize, -2), 6))
        #endif
    }

    private var textSizeCategory: DynamicTypeSize {
        #if os(macOS)
            zooms ? Zoom.size(zoom) : .large
        #else
            dynamicTypeSize
        #endif
    }
}

#if os(macOS)
    extension View {
        /// A sheet at its window's zoom.
        func keepsWindowZoom() -> some View { modifier(SheetZoom()) }
    }

    private struct SheetZoom: ViewModifier {
        @Environment(\.windowZoom) private var zoom

        func body(content: Content) -> some View { content.modifier(MacZoom(size: zoom)) }
    }

    /// Carries the zoom as the window's Dynamic Type size (`Zoom`), and grows the text of the
    /// system's own controls, which take the default font, with it.
    private struct MacZoom: ViewModifier {
        let size: DynamicTypeSize

        func body(content: Content) -> some View {
            // At actual size the default font stays unset, so a control's own size
            // (`controlSize`) still picks its text. Not an `if`: that would rebuild the window.
            content
                .dynamicTypeSize(size)
                .font(size == .large ? nil : .system(size: NSFont.systemFontSize * Zoom.factor(size)))
        }
    }
#endif

private struct MessageFont: ViewModifier {
    @Environment(\.messageTextSize) private var size

    func body(content: Content) -> some View {
        content.font(.system(size: size)).lineSpacing(Theme.messageLineSpacing)
    }
}

extension View {
    func messageFont() -> some View { modifier(MessageFont()) }
}
