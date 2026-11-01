import SwiftUI

/// Device-local preferences shared with the native app shell.
public enum AppPreferences {
    public static let appearanceKey = "appearance"
    public static let textSizeKey = "chatTextSize"
    public static let commandReturnKey = "commandReturnToSend"
    public static let notificationsKey = "taskNotifications"
    public static let notificationSoundKey = "notificationSound"
    public static let notificationPreviewsKey = "notificationPreviews"
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

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .environment(\.messageTextSize, Theme.messageSize + CGFloat(min(max(textSize, -2), 6)))
    }
}

private struct MessageFont: ViewModifier {
    @Environment(\.messageTextSize) private var size

    func body(content: Content) -> some View {
        content.font(.system(size: size)).lineSpacing(4)
    }
}

extension View {
    func messageFont() -> some View { modifier(MessageFont()) }
}
