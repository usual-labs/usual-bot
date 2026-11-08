import SwiftUI

/// Device-local preferences shared with the native app shell.
public enum AppPreferences {
    public static let appearanceKey = "appearance"
    public static let textSizeKey = "chatTextSize"
    public static let commandReturnKey = "commandReturnToSend"
    public static let notificationsKey = "taskNotifications"
    public static let messageNotificationsKey = "messageNotifications"
    public static let needsYouNotificationsKey = "needsYouNotifications"
    public static let notificationSoundKey = "notificationSound"
    public static let notificationPreviewsKey = "notificationPreviews"
    /// Off: an agent's message appears once it's written, not word by word.
    public static let streamRepliesKey = "streamReplies"
}

extension EnvironmentValues {
    @Entry var messageTextSize: CGFloat = Theme.messageSize
}

extension View {
    /// Apply at each window and panel root so preferences update every surface immediately.
    public func appPreferences() -> some View { modifier(PreferencesStyle()) }
}

private struct PreferencesStyle: ViewModifier {
    @AppStorage(AppPreferences.appearanceKey) private var appearance = "system"
    @AppStorage(AppPreferences.textSizeKey) private var textSize = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The in-app setting picks the size at the default text size; Dynamic Type grows it from there.
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .environment(
                \.messageTextSize,
                Theme.scaled(Theme.messageSize + CGFloat(min(max(textSize, -2), 6)), for: dynamicTypeSize)
            )
            // The pointing hand over buttons that pick no style; the rest wrap theirs in
            // `.clickable(_:)`.
            .buttonStyle(.clickable(.automatic))
    }
}

private struct MessageFont: ViewModifier {
    @Environment(\.messageTextSize) private var size

    func body(content: Content) -> some View {
        content.font(.system(size: size)).lineSpacing(Theme.messageLineSpacing)
    }
}

extension View {
    func messageFont() -> some View { modifier(MessageFont()) }
}
