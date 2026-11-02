import SwiftUI

extension View {
    /// The pointing hand on the Mac over anything that answers a click, so you can tell what does.
    /// The plain arrow stays while it's disabled. iPhone has no pointer to change.
    public func clickable() -> some View {
        modifier(Clickable())
    }
}

private struct Clickable: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        #if os(macOS)
            content.pointerStyle(isEnabled ? .link : nil)
        #else
            content
        #endif
    }
}

/// `.plain`, with the pointing hand on the Mac. Use it wherever a button would be `.plain`.
public struct ClickableButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(.plain).clickable()
    }
}

extension PrimitiveButtonStyle where Self == ClickableButtonStyle {
    public static var clickable: ClickableButtonStyle { ClickableButtonStyle() }
}
