import Foundation

/// What runs around an inline widget's page: the app's theme before the page's own styles, and a
/// script that reports how big the page is. Both run in their own script world (`WidgetFrame`),
/// so the page can neither see them nor fake a size. Matches Hermes's desktop app
/// (`inline-preview-directive.tsx`), which is what agents are told to write for.
enum WidgetPage {
    /// The frame's height stays within these; past the top, the page scrolls inside it.
    static let minHeight: CGFloat = 120
    static let maxHeight: CGFloat = 1200
    /// Before the page has measured itself, with no `height` attribute.
    static let startHeight: CGFloat = 280
    /// Ignored changes in height, so a page sized to the frame can't make it creep.
    static let tolerance: CGFloat = 4

    static func clamped(_ height: CGFloat) -> CGFloat {
        min(maxHeight, max(minHeight, height))
    }

    /// The frame's height before measuring: the `height` attribute, or `startHeight`.
    static func startHeight(_ attribute: Int?) -> CGFloat {
        attribute.map { clamped(CGFloat($0)) } ?? startHeight
    }

    /// The app's look, under the names Hermes gives widgets (`var(--foreground)` and kin).
    struct Theme: Equatable {
        var dark: Bool
        var foreground: String
        var mutedForeground: String
        var accent: String
        var border: String
        var card: String
        /// The chat's text size, in points.
        var fontSize: Double

        /// The style sheet, first in the page so the page's own rules win: a page with its own
        /// design keeps it, and one without reads as part of the chat.
        var css: String {
            let size = (fontSize * 10).rounded() / 10
            return ":root{color-scheme:\(dark ? "dark" : "light");--foreground:\(foreground);"
                + "--muted-foreground:\(mutedForeground);--accent:\(accent);--border:\(border);--card:\(card)}"
                + "html,body{margin:0;padding:0;background:transparent;color:var(--foreground);"
                + "font:\(size)px -apple-system,system-ui,sans-serif;-webkit-text-size-adjust:100%}"
        }
    }

    /// A CSS colour from sRGB components between 0 and 1.
    static func css(red: Double, green: Double, blue: Double, opacity: Double = 1) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let rgb = "\(byte(red)) \(byte(green)) \(byte(blue))"
        return opacity >= 1 ? "rgb(\(rgb))" : "rgb(\(rgb) / \((opacity * 1000).rounded() / 1000))"
    }

    static let styleID = "usual-widget-theme"

    /// Puts the theme first in the document, before any of the page has loaded, with a phone-width
    /// viewport the page's own can replace. Without one iPhone lays a page out 980 points wide.
    static func themeScript(_ theme: Theme) -> String {
        """
        (function(){var d=document.documentElement;\
        var m=document.createElement("meta");m.name="viewport";m.content="width=device-width,initial-scale=1";\
        var s=document.createElement("style");s.id=\(json(styleID));s.textContent=\(json(theme.css));\
        d.insertBefore(s,d.firstChild);d.insertBefore(m,s)})()
        """
    }

    /// Swaps the theme in a page already running, so it keeps its state when the app turns dark.
    static func retheme(_ theme: Theme) -> String {
        "(function(){var s=document.getElementById(\(json(styleID)));if(s)s.textContent=\(json(theme.css))})()"
    }

    static let sizeChannel = "size"

    /// Reports the page's size whenever it changes. Height is the body's (the document's own is
    /// never less than the frame, so it couldn't shrink); width is the span of the body's children,
    /// so a fixed-width widget can sit at its own width and a fluid page fills the message.
    static let measureScript = """
        (function(){var lastH=0,lastW=0;\
        function post(){var b=document.body;if(!b)return;var r=b.getBoundingClientRect();\
        var h=Math.max(b.scrollHeight,r.bottom+scrollY+(parseFloat(getComputedStyle(b).marginBottom)||0));\
        var L=Infinity,R=0,k=b.children;for(var i=0;i<k.length;i++){var c=k[i].getBoundingClientRect();\
        if(c.width===0&&c.height===0)continue;if(c.left<L)L=c.left;if(c.right>R)R=c.right}\
        var w=R>L?Math.ceil(R-L):0;h=Math.ceil(h);\
        if(Math.abs(h-lastH)>1||Math.abs(w-lastW)>1){lastH=h;lastW=w;\
        webkit.messageHandlers.\(sizeChannel).postMessage({height:h,width:w})}}\
        if(typeof ResizeObserver==="function"){var o=new ResizeObserver(post);o.observe(document.documentElement);\
        if(document.body)o.observe(document.body)}addEventListener("load",post);post()})()
        """

    /// The size in a report from `measureScript`; `nil` for anything malformed. `width` is 0 when
    /// the page has nothing to measure.
    static func size(from body: Any) -> (height: CGFloat, width: CGFloat)? {
        guard let report = body as? [String: Any], let height = (report["height"] as? NSNumber)?.doubleValue,
            height.isFinite, height > 0
        else { return nil }
        let width = (report["width"] as? NSNumber)?.doubleValue ?? 0
        return (height.rounded(), width.isFinite && width > 0 ? width.rounded() : 0)
    }

    private static func json(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }
}
