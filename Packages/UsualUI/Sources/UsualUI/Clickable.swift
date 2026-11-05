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

/// A button style with the pointing hand on the Mac: `.clickable` is `.plain`, and
/// `.clickable(.bordered)` wraps any other style. Like any style it reaches every button inside
/// what it's set on, so `RootView` sets `.clickable(.automatic)` for buttons that pick no style.
public struct ClickableButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    let base: Base

    public func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(base).clickable()
    }
}

extension PrimitiveButtonStyle where Self == ClickableButtonStyle<PlainButtonStyle> {
    public static var clickable: Self { ClickableButtonStyle(base: .plain) }
}

extension PrimitiveButtonStyle {
    public static func clickable<Base: PrimitiveButtonStyle>(_ base: Base) -> Self
    where Self == ClickableButtonStyle<Base> {
        ClickableButtonStyle(base: base)
    }
}
