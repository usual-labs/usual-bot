import SwiftUI

/// The Mac's View ▸ Zoom (⌘+, ⌘−, ⌘0): the whole window grows or shrinks by one factor, the way a
/// browser zooms a page. The Mac has no Dynamic Type, so the zoom rides on the window's
/// `dynamicTypeSize`: `appPreferences()` sets the level's size there, and `Theme.scaled` and
/// `Theme.zoomed` turn it back into the factor. Everything that already grows with Dynamic Type on
/// iPhone (`scaledFont`, `ScaledSize`, avatars) grows with the zoom on the Mac without more code.
public enum Zoom {
    public static let key = "zoom"

    /// The levels, from the smallest. Only sizes below the accessibility ones: those make rows wrap
    /// as they do for very large text on iPhone, which a zoomed Mac window doesn't need.
    static let levels: [DynamicTypeSize] = [.xSmall, .small, .large, .xLarge, .xxLarge, .xxxLarge]
    /// The level that draws everything at its own size.
    static let actualSize = 2

    /// How much bigger than its own size a level draws, as a fraction.
    static func factor(_ size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 0.8
        case .small: 0.9
        case .medium: 0.95
        case .large: 1
        case .xLarge: 1.1
        case .xxLarge: 1.25
        case .xxxLarge: 1.5
        default: 1.5
        }
    }

    /// A stored level, kept in range.
    static func level(_ stored: Int) -> Int { min(max(stored, 0), levels.count - 1) }
    static func size(_ stored: Int) -> DynamicTypeSize { levels[level(stored)] }
    static func zoomedIn(_ stored: Int) -> Int { level(level(stored) + 1) }
    static func zoomedOut(_ stored: Int) -> Int { level(level(stored) - 1) }
    static func canZoomIn(_ stored: Int) -> Bool { level(stored) < levels.count - 1 }
    static func canZoomOut(_ stored: Int) -> Bool { level(stored) > 0 }

    /// "125%", for the menu and Settings.
    static func percent(_ stored: Int) -> String {
        "\(Int((factor(size(stored)) * 100).rounded()))%"
    }

    /// The level before anyone zooms: the old Chat text size, which the Mac no longer shows, picked
    /// its nearest level, so text someone made larger doesn't shrink after the update.
    public static func initialLevel(chatTextSize: Int) -> Int {
        switch chatTextSize {
        case ..<0: 1
        case 1...4: 4
        case 5...: 5
        default: actualSize
        }
    }
}

extension Theme {
    /// A length at the default size, grown by the Mac's zoom. iPhone keeps it as it is: lengths that
    /// should follow Dynamic Type there use `ScaledSize`.
    static func zoomed(_ length: CGFloat, for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        #if os(macOS)
            (length * Zoom.factor(dynamicTypeSize)).rounded()
        #else
            length
        #endif
    }
}

/// A length that grows with the Mac's zoom and stays put on iPhone, such as a column's width.
@propertyWrapper struct Zoomed: DynamicProperty {
    // The window's zoom, which a sheet's frame set outside it gets too (`windowZoom`).
    #if os(macOS)
        @Environment(\.windowZoom) private var dynamicTypeSize
    #else
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    private let length: CGFloat

    init(wrappedValue: CGFloat) { length = wrappedValue }

    var wrappedValue: CGFloat { Theme.zoomed(length, for: dynamicTypeSize) }
}

/// `@ScaledMetric` that also follows the Mac's zoom, which `@ScaledMetric` ignores there.
@propertyWrapper struct ScaledSize: DynamicProperty {
    #if os(iOS)
        @ScaledMetric private var metric: CGFloat
    #else
        // The window's zoom, which a sheet's frame set outside it gets too (`windowZoom`).
        #if os(macOS)
            @Environment(\.windowZoom) private var dynamicTypeSize
        #else
            @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        #endif
        private let length: CGFloat
    #endif

    init(wrappedValue: CGFloat, relativeTo textStyle: Font.TextStyle = .body) {
        #if os(iOS)
            _metric = ScaledMetric(wrappedValue: wrappedValue, relativeTo: textStyle)
        #else
            length = wrappedValue
        #endif
    }

    var wrappedValue: CGFloat {
        #if os(iOS)
            metric
        #else
            Theme.zoomed(length, for: dynamicTypeSize)
        #endif
    }
}

extension View {
    /// `frame(width:height:alignment:)` at the default size, grown by the Mac's zoom.
    func zoomedFrame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        modifier(ZoomedFrame(width: width, height: height, alignment: alignment))
    }

    /// `frame(minWidth:maxWidth:minHeight:alignment:)` at the default size, grown by the Mac's zoom.
    func zoomedFrame(
        minWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        modifier(
            ZoomedFlexibleFrame(minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, alignment: alignment))
    }
}

private struct ZoomedFrame: ViewModifier {
    let width: CGFloat?
    let height: CGFloat?
    let alignment: Alignment
    // The window's zoom, which a sheet's frame set outside it gets too (`windowZoom`).
    #if os(macOS)
        @Environment(\.windowZoom) private var dynamicTypeSize
    #else
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    func body(content: Content) -> some View {
        content.frame(
            width: width.map { Theme.zoomed($0, for: dynamicTypeSize) },
            height: height.map { Theme.zoomed($0, for: dynamicTypeSize) },
            alignment: alignment)
    }
}

private struct ZoomedFlexibleFrame: ViewModifier {
    let minWidth: CGFloat?
    let maxWidth: CGFloat?
    let minHeight: CGFloat?
    let alignment: Alignment
    // The window's zoom, which a sheet's frame set outside it gets too (`windowZoom`).
    #if os(macOS)
        @Environment(\.windowZoom) private var dynamicTypeSize
    #else
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    func body(content: Content) -> some View {
        content.frame(
            minWidth: minWidth.map { Theme.zoomed($0, for: dynamicTypeSize) },
            maxWidth: maxWidth.map { Theme.zoomed($0, for: dynamicTypeSize) },
            minHeight: minHeight.map { Theme.zoomed($0, for: dynamicTypeSize) },
            alignment: alignment)
    }
}

extension View {
    /// A system font that stays at `size` on iPhone, for a glyph in a fixed circle, and grows with
    /// the Mac's zoom along with its circle.
    func zoomedFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(ZoomedFont(size: size, weight: weight, design: design))
    }
}

private struct ZoomedFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?
    // The window's zoom, which a sheet's frame set outside it gets too (`windowZoom`).
    #if os(macOS)
        @Environment(\.windowZoom) private var dynamicTypeSize
    #else
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    func body(content: Content) -> some View {
        content.font(.system(size: Theme.zoomed(size, for: dynamicTypeSize), weight: weight, design: design))
    }
}

extension View {
    /// A text style's font, grown with the Mac's zoom, which text styles ignore there. iPhone gets
    /// the text style itself, Dynamic Type and all.
    func zoomedFont(_ style: Font.TextStyle) -> some View {
        #if os(macOS)
            modifier(ZoomedFont(size: Zoom.macSize(style), weight: style == .headline ? .bold : nil, design: nil))
        #else
            font(.system(style))
        #endif
    }
}

#if os(macOS)
    extension Zoom {
        /// What each text style measures on the Mac, which has no Dynamic Type to change it.
        static func macSize(_ style: Font.TextStyle) -> CGFloat {
            switch style {
            case .largeTitle: 26
            case .title: 22
            case .title2: 17
            case .title3: 15
            case .headline, .body: 13
            case .callout: 12
            case .subheadline: 11
            default: 10
            }
        }
    }
#endif

extension Zoom {
    /// The zoom kept in `defaults`, for windows the app sizes itself, such as the quick message panel.
    public static func factor(for defaults: UserDefaults) -> CGFloat {
        let stored = defaults.object(forKey: key) as? Int
        return factor(size(stored ?? initialLevel(chatTextSize: defaults.integer(forKey: AppPreferences.textSizeKey))))
    }
}
