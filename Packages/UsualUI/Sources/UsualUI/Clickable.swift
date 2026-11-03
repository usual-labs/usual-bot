import SwiftUI

extension View {
    /// The pointing hand on the Mac over anything that answers a click, so you can tell what does.
    /// The plain arrow stays while it's disabled. iPhone has no pointer to change.
    public func clickable() -> some View {
        modifier(Clickable())
    }
}

extension View {
    /// On iPhone, a hit area at least 44 pt each way around a control drawn `width` by `height`,
    /// without moving anything: the extra spills over what's around it. Use inside a button's
    /// label, after its frame. The Mac keeps its pointer-sized targets.
    func touchTarget(width: CGFloat, height: CGFloat) -> some View {
        #if os(iOS)
            let dx = max(0, 44 - width) / 2
            let dy = max(0, 44 - height) / 2
            return padding(.horizontal, dx).padding(.vertical, dy).contentShape(Rectangle())
                .padding(.horizontal, -dx).padding(.vertical, -dy)
        #else
            return self
        #endif
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
