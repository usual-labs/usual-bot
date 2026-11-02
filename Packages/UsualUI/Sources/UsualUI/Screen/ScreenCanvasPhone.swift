#if os(iOS)
    import HermesKit
    import SwiftUI
    import UIKit

    /// The screen, scaled to fit; pinch to zoom. While you're in control: tap to click, touch and
    /// hold to right-click, drag to drag, two fingers to scroll, and the bar's keyboard to type.
    /// Watching, one finger moves around a zoomed screen.
    struct ScreenCanvas: UIViewRepresentable {
        let screen: BotScreen
        let frame: CGImage
        @Binding var showsKeyboard: Bool

        func makeUIView(context: Context) -> CanvasScrollView {
            CanvasScrollView()
        }

        func updateUIView(_ view: CanvasScrollView, context: Context) {
            view.screen = screen
            view.show(frame)
            view.controlling = screen.control == .you
            view.keyboard.screen = screen
            if showsKeyboard, !view.keyboard.isFirstResponder {
                view.keyboard.becomeFirstResponder()
            } else if !showsKeyboard, view.keyboard.isFirstResponder {
                view.keyboard.resignFirstResponder()
            }
        }
    }

    final class CanvasScrollView: UIScrollView, UIScrollViewDelegate {
        var screen: BotScreen?
        let keyboard = KeyInputView()
        private let picture = UIImageView()
        private var pixels = CGSize.zero
        private var mouseHeld = false
        private var scrollCarry: CGFloat = 0
        private lazy var drag = UIPanGestureRecognizer(target: self, action: #selector(dragged))
        private lazy var twoFingers = UIPanGestureRecognizer(target: self, action: #selector(scrolled))

        var controlling = false {
            didSet {
                guard controlling != oldValue else { return }
                // In control, one finger is the mouse; watching, it moves around the zoomed screen.
                panGestureRecognizer.isEnabled = !controlling
                drag.isEnabled = controlling
                twoFingers.isEnabled = controlling
                picture.accessibilityHint =
                    controlling
                    ? String(localized: "Tap to click, drag to drag, two fingers to scroll.")
                    : String(localized: "Take over to use the computer.")
            }
        }

        init() {
            super.init(frame: .zero)
            delegate = self
            minimumZoomScale = 1
            maximumZoomScale = 5
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            backgroundColor = .black
            picture.isUserInteractionEnabled = true
            picture.isAccessibilityElement = true
            picture.accessibilityLabel = String(localized: "The agent's screen")
            picture.accessibilityTraits = .image
            picture.accessibilityHint = String(localized: "Take over to use the computer.")
            addSubview(picture)
            addSubview(keyboard)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
            twoFingers.minimumNumberOfTouches = 2
            twoFingers.maximumNumberOfTouches = 2
            drag.maximumNumberOfTouches = 1
            drag.isEnabled = false
            twoFingers.isEnabled = false
            for gesture in [tap, hold, drag, twoFingers] { picture.addGestureRecognizer(gesture) }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func show(_ frame: CGImage) {
            let size = CGSize(width: frame.width, height: frame.height)
            picture.image = UIImage(cgImage: frame)
            if size != pixels {
                pixels = size
                setNeedsLayout()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard pixels.width > 0, pixels.height > 0, zoomScale == 1 else {
                centre()
                return
            }
            let scale = min(bounds.width / pixels.width, bounds.height / pixels.height)
            picture.frame = CGRect(
                origin: .zero, size: CGSize(width: pixels.width * scale, height: pixels.height * scale))
            contentSize = picture.frame.size
            centre()
        }

        /// Keeps a screen smaller than the view in its middle.
        private func centre() {
            let x = max((bounds.width - picture.frame.width) / 2, 0)
            let y = max((bounds.height - picture.frame.height) / 2, 0)
            contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centre() }

        /// A touch in the screen's pixels.
        private func point(_ gesture: UIGestureRecognizer) -> CGPoint? {
            let at = gesture.location(in: picture)
            let size = picture.bounds.size
            guard size.width > 0, size.height > 0 else { return nil }
            return CGPoint(
                x: min(max(at.x / size.width * pixels.width, 0), pixels.width - 1),
                y: min(max(at.y / size.height * pixels.height, 0), pixels.height - 1))
        }

        private func click(_ gesture: UIGestureRecognizer, buttons: UInt8) {
            guard controlling, let screen, let at = point(gesture) else { return }
            screen.pointer(x: at.x, y: at.y, buttons: 0)
            screen.pointer(x: at.x, y: at.y, buttons: buttons)
            screen.pointer(x: at.x, y: at.y, buttons: 0)
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) { click(gesture, buttons: 1) }

        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began, !mouseHeld { click(gesture, buttons: 4) }
        }

        @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
            guard let screen, let at = point(gesture) else { return }
            switch gesture.state {
            case .began:
                mouseHeld = true
                screen.pointer(x: at.x, y: at.y, buttons: 0)
                screen.pointer(x: at.x, y: at.y, buttons: 1)
            case .changed:
                screen.pointer(x: at.x, y: at.y, buttons: 1)
            default:
                mouseHeld = false
                screen.pointer(x: at.x, y: at.y, buttons: 0)
            }
        }

        /// Two fingers up or down: one wheel click per 20 points, natural direction.
        @objc private func scrolled(_ gesture: UIPanGestureRecognizer) {
            guard let screen, let at = point(gesture) else { return }
            if gesture.state == .began { scrollCarry = 0 }
            scrollCarry += gesture.translation(in: self).y
            gesture.setTranslation(.zero, in: self)
            while abs(scrollCarry) >= 20 {
                let mask: UInt8 = scrollCarry > 0 ? 8 : 16
                screen.pointer(x: at.x, y: at.y, buttons: mask)
                screen.pointer(x: at.x, y: at.y, buttons: 0)
                scrollCarry -= scrollCarry > 0 ? 20 : -20
            }
        }
    }

    /// Takes the on-screen or a hardware keyboard's typing for the agent's screen.
    final class KeyInputView: UIView, UIKeyInput {
        var screen: BotScreen?

        override var canBecomeFirstResponder: Bool { true }
        var hasText: Bool { true }
        var autocorrectionType: UITextAutocorrectionType = .no
        var autocapitalizationType: UITextAutocapitalizationType = .none
        var spellCheckingType: UITextSpellCheckingType = .no
        var smartQuotesType: UITextSmartQuotesType = .no
        var smartDashesType: UITextSmartDashesType = .no

        func insertText(_ text: String) {
            screen?.type(text)
        }

        func deleteBackward() {
            screen?.key(Keysym.backspace.value, down: true)
            screen?.key(Keysym.backspace.value, down: false)
        }
    }
#endif
