#if os(macOS)
    import AppKit
    import SwiftUI

    /// A message's words on the Mac, in one AppKit text view: a drag selects across paragraphs,
    /// headings, list items and quotes, as in a web page. With words selected, Reply (its button,
    /// the right-click menu or ⌘L) opens a field under them for what you say to them; Return quotes
    /// them in your next message with your reply under the quote.
    struct MessageText: View {
        let content: MessageTextContent
        @Environment(\.quoteSelection) private var quoteSelection
        @State private var selection: SelectedWords?
        /// The words whose Reply field is open.
        @State private var replying: SelectedWords?
        @State private var reply = ""
        /// The button's size once it's laid out: its words and their size vary.
        @State private var buttonSize = CGSize(width: 90, height: ReplyButton.height)

        var body: some View {
            let anchor = quoteSelection == nil || replying != nil ? nil : selection?.anchor
            let button = anchor.map { ReplyButton.frame(over: $0, size: buttonSize) }
            MessageTextView(
                content: content, reply: quoteSelection == nil ? nil : { replying = $0 }, holding: replying != nil,
                button: button
            ) { selection = $0 }
            .overlay {
                if let selection, let button {
                    ReplyButton { replying = selection }
                        .onGeometryChange(for: CGSize.self) {
                            $0.size
                        } action: {
                            buttonSize = $0
                        }
                        .position(x: button.midX, y: button.midY)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: selection)
            .popover(item: $replying, attachmentAnchor: .rect(.rect(replying?.bounds ?? .zero)), arrowEdge: .bottom) {
                words in
                ReplyField(excerpt: ReplyField.excerpt(of: words.text), note: $reply) {
                    quoteSelection?(words.text, reply)
                    replying = nil
                }
            }
            // Kept or not, the words are let go of, and the next Reply starts empty.
            .onChange(of: replying) { old, new in
                guard new == nil, let old else { return }
                old.release()
                reply = ""
            }
        }
    }

    /// Words selected in a message, and where to show Reply: the selection's top, in the text
    /// view's coordinates.
    struct SelectedWords: Equatable, Identifiable {
        let text: String
        let anchor: CGPoint
        /// Around the selected lines, for the Reply field to open under.
        let bounds: CGRect
        /// Clears the selection.
        let release: () -> Void

        var id: String { text }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.text == rhs.text && lhs.anchor == rhs.anchor && lhs.bounds == rhs.bounds
        }
    }

    /// A small pill over a selection, as in a coding agent's chat. Solid, with a hairline and a
    /// soft shadow: as glass, the words under it showed through its own.
    private struct ReplyButton: View {
        let action: () -> Void
        static let height: CGFloat = 30

        /// Where it sits in the text view: centred over where the drag ended, just above the
        /// selection's first line, and not far past the text's leading edge.
        static func frame(over anchor: CGPoint, size: CGSize) -> CGRect {
            CGRect(
                x: max(anchor.x - size.width / 2, -8), y: anchor.y - size.height - 4, width: size.width,
                height: size.height)
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Text("Reply")
                    Text("⌘L")
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Theme.ink)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .zoomedFrame(height: Self.height)
                .background(Theme.floating, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.clickable)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .fixedSize()
            .help("Reply to the selected words")
            .accessibilityLabel(Text("Reply"))
        }
    }

    private struct MessageTextView: NSViewRepresentable {
        let content: MessageTextContent
        let reply: ((SelectedWords) -> Void)?
        /// The Reply field is open: the selection stays while you type in it.
        let holding: Bool
        /// Where Reply is drawn over the text.
        let button: CGRect?
        let selected: (SelectedWords?) -> Void

        func makeNSView(context: Context) -> SelectableTextView {
            SelectableTextView()
        }

        func updateNSView(_ view: SelectableTextView, context: Context) {
            view.reply = reply
            view.holdsSelection = holding
            view.selected = selected
            view.button = button
            view.show(content)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView view: SelectableTextView, context: Context) -> CGSize? {
            view.show(content)
            return view.fittingSize(width: proposal.width)
        }
    }

    /// Selectable, never editable. Measures itself with a second layout manager on the same text,
    /// so sizing for SwiftUI doesn't disturb what's shown.
    final class SelectableTextView: NSTextView {
        /// Opens the Reply field for the selected words; `nil` where messages can't be replied to.
        var reply: ((SelectedWords) -> Void)?
        /// While the Reply field is open, the selection stays as focus moves into it.
        var holdsSelection = false
        var selected: (SelectedWords?) -> Void = { _ in }
        /// Where Reply is drawn over this text, in its coordinates. The pointer there is the
        /// button's.
        var button: CGRect? {
            didSet { if button != oldValue { window?.invalidateCursorRects(for: self) } }
        }
        private var content: MessageTextContent?
        private let measuring = NSLayoutManager()
        private let measuringContainer = NSTextContainer()
        /// Sizes for the widths SwiftUI asked about, until the text changes.
        private var sizes: [CGFloat: CGSize] = [:]

        init() {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            container.widthTracksTextView = true
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            measuringContainer.lineFragmentPadding = 0
            measuring.addTextContainer(measuringContainer)
            storage.addLayoutManager(measuring)
            super.init(frame: .zero, textContainer: container)
            isEditable = false
            isSelectable = true
            drawsBackground = false
            isRichText = true
            importsGraphics = false
            allowsUndo = false
            usesFindBar = false
            isAutomaticLinkDetectionEnabled = false
            textContainerInset = .zero
            isVerticallyResizable = false
            isHorizontallyResizable = false
            focusRingType = .none
            delegate = self
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
            super.init(frame: frameRect, textContainer: container)
        }

        func show(_ content: MessageTextContent) {
            guard content != self.content, let textStorage else { return }
            self.content = content
            sizes = [:]
            let link: NSColor
            if case .mine = content { link = RichText.userInk } else { link = .linkColor }
            linkTextAttributes = [
                .foregroundColor: link, .underlineStyle: NSUnderlineStyle.single.rawValue,
                .cursor: NSCursor.pointingHand,
            ]
            textStorage.setAttributedString(RichText.string(for: content))
        }

        /// As wide as its longest line, up to `width`, and as tall as its lines at that width.
        func fittingSize(width: CGFloat?) -> CGSize {
            // A width of 0 asks for the narrowest; one word a line is no use in a message.
            let width = min(max(width ?? .infinity, 40), 100_000)
            if let size = sizes[width] { return size }
            measuringContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
            measuring.ensureLayout(for: measuringContainer)
            let used = measuring.usedRect(for: measuringContainer)
            let size = CGSize(width: min(ceil(used.width), width), height: ceil(used.height))
            sizes[width] = size
            return size
        }

        // MARK: Selection

        override func setSelectedRanges(
            _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
        ) {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            if !stillSelecting { reportSelection() }
        }

        /// One selection in the conversation at a time: clicking elsewhere, or into the message
        /// box, lets go of it. Typing a reply to it doesn't.
        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned, !holdsSelection { setSelectedRange(NSRange(location: selectedRange().location, length: 0)) }
            return resigned
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            // The lines rewrapped, so the button moves with the selection's first line.
            if selectedRange().length > 0 { reportSelection() }
        }

        /// The selected words, as they'd be pasted.
        var selectedWords: String {
            let string = self.string as NSString
            return selectedRanges.map { RichText.plain(string.substring(with: $0.rangeValue)) }
                .joined(separator: "\n")
        }

        private func reportSelection() {
            let words = currentWords()
            // Later: this can run while SwiftUI updates the view, which mustn't change its state.
            let selected = selected
            Task { @MainActor in selected(words) }
        }

        /// The selection, where Reply sits over it and the lines it covers.
        private func currentWords() -> SelectedWords? {
            let range = selectedRange()
            guard range.length > 0, let layoutManager, let textContainer else { return nil }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            // Over where the drag ended; from the keyboard, over the selection's middle.
            var x = bounds.midX
            if let event = NSApp?.currentEvent, event.window === window,
                [.leftMouseUp, .leftMouseDragged, .leftMouseDown].contains(event.type)
            {
                x = convert(event.locationInWindow, from: nil).x
            }
            return SelectedWords(
                text: selectedWords, anchor: CGPoint(x: min(max(x, 0), self.bounds.width), y: bounds.minY),
                bounds: bounds,
                release: { [weak self] in
                    guard let self else { return }
                    setSelectedRange(NSRange(location: NSMaxRange(selectedRange()), length: 0))
                })
        }

        /// Opens the Reply field under the selection.
        @objc func replyToSelection(_ sender: Any?) {
            guard let reply, let words = currentWords() else { return }
            reply(words)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers?.lowercased() == "l", reply != nil,
                window?.firstResponder === self, selectedRange().length > 0
            {
                replyToSelection(nil)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        /// Right-clicking the selection offers Reply and the text's own commands; a link, Open Link
        /// and Copy Link; anywhere else, the message's menu (React, Reply, Copy).
        override func menu(for event: NSEvent) -> NSMenu? {
            let range = selectedRange()
            let point = convert(event.locationInWindow, from: nil)
            let index = characterIndexForInsertion(at: point)
            let inSelection = range.length > 0 && index >= range.location && index <= NSMaxRange(range)
            if !inSelection, let url = link(at: point) { return Self.linkMenu(for: url) }
            guard inSelection,
                let menu = super.menu(for: event)
            else { return nil }
            Self.dropEditing(from: menu)
            if reply != nil {
                let item = NSMenuItem(
                    title: String(localized: "Reply"), action: #selector(replyToSelection(_:)), keyEquivalent: "l")
                item.keyEquivalentModifierMask = .command
                item.image = NSImage(systemSymbolName: "arrowshape.turn.up.left", accessibilityDescription: nil)
                item.target = self
                menu.insertItem(item, at: 0)
                menu.insertItem(.separator(), at: 1)
            }
            return menu
        }

        /// The web or mail link under the pointer. A link to a path names a file on the gateway,
        /// which this Mac can't open, so it gets the message's menu.
        private func link(at point: NSPoint) -> URL? {
            guard let layoutManager, let textContainer, textStorage?.length ?? 0 > 0 else { return nil }
            let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            var fraction: CGFloat = 0
            let glyph = layoutManager.glyphIndex(
                for: inContainer, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
            // Past the end of a line, the nearest glyph isn't under the pointer.
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            guard glyphRect.contains(inContainer) else { return nil }
            let index = layoutManager.characterIndexForGlyph(at: glyph)
            guard let storage = textStorage, index < storage.length else { return nil }
            let value = storage.attribute(.link, at: index, effectiveRange: nil)
            let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
            guard let url, let scheme = url.scheme, scheme != "file" else { return nil }
            return url
        }

        /// As in a browser: open the link or copy its address, rather than the whole message.
        private static func linkMenu(for url: URL) -> NSMenu {
            let menu = NSMenu()
            let open = NSMenuItem(
                title: String(localized: "Open Link"), action: #selector(LinkAction.open), keyEquivalent: "")
            open.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
            let copy = NSMenuItem(
                title: String(localized: "Copy Link"), action: #selector(LinkAction.copyAddress), keyEquivalent: "")
            copy.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
            let target = LinkAction(url: url)
            for item in [open, copy] {
                item.target = target
                // A menu item holds its target weakly; the object keeps it for the menu's life.
                item.representedObject = target
                menu.addItem(item)
            }
            return menu
        }

        /// Leaves Look Up, Translate, Search, Copy, Share and Speech: the words can't be edited, so
        /// Cut, Paste, Font, Spelling and Substitutions don't apply.
        private static func dropEditing(from menu: NSMenu) {
            let editing: Set<Selector> = [
                #selector(cut(_:)), #selector(paste(_:)), #selector(pasteAsPlainText(_:)),
                #selector(pasteAsRichText(_:)),
            ]
            for item in menu.items.reversed() {
                let drop: Bool
                if let submenu = item.submenu {
                    drop = !submenu.items.contains { $0.action == #selector(startSpeaking(_:)) }
                } else {
                    drop = item.action.map(editing.contains) ?? false
                }
                if drop { menu.removeItem(item) }
            }
            // No separator at either end or two in a row.
            for (index, item) in menu.items.enumerated().reversed() where item.isSeparatorItem {
                let next = index + 1 < menu.items.count ? menu.items[index + 1] : nil
                if index == 0 || next == nil || next?.isSeparatorItem == true { menu.removeItem(item) }
            }
        }

        /// Copies the words as they read, with list markers but no layout tabs.
        override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
            let written = super.writeSelection(to: pboard, types: types)
            if written, types.contains(.string) { pboard.setString(selectedWords, forType: .string) }
            return written
        }

        // MARK: Pointer

        // A text view shows the I-beam all over itself, by a cursor rectangle and again each time
        // the pointer moves. SwiftUI draws Reply and Jump to Latest over it and sets the
        // pointing hand only as the pointer arrives, so the I-beam came back while it moved across
        // them, or as the text scrolled under them.

        /// With Reply or a `HandArea` over the text, the pointing hand there and the I-beam
        /// around it; `nil` without, when the text view's own I-beam is right.
        func pointerRects() -> [(rect: NSRect, cursor: NSCursor)]? {
            let text = visibleRect
            let hands = handRects().map { $0.intersection(text) }.filter { !$0.isEmpty }
            guard !hands.isEmpty else { return nil }
            let beams = hands.reduce([text]) { rects, hand in rects.flatMap { Self.remove(hand, from: $0) } }
            return hands.map { ($0, .pointingHand) } + beams.map { ($0, .iBeam) }
        }

        /// Reply, and every `HandArea` in this window, in this view's coordinates.
        private func handRects() -> [NSRect] {
            let floating = HandArea.all.allObjects.filter { $0.window === window && window != nil }
            return (button.map { [$0] } ?? []) + floating.map { convert($0.bounds, from: $0) }
        }

        /// What's left of `rect` without `hole`, as up to four rectangles.
        private static func remove(_ hole: NSRect, from rect: NSRect) -> [NSRect] {
            let hole = rect.intersection(hole)
            guard !hole.isEmpty else { return [rect] }
            return [
                NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: hole.minY - rect.minY),
                NSRect(x: rect.minX, y: hole.maxY, width: rect.width, height: rect.maxY - hole.maxY),
                NSRect(x: rect.minX, y: hole.minY, width: hole.minX - rect.minX, height: hole.height),
                NSRect(x: hole.maxX, y: hole.minY, width: rect.maxX - hole.maxX, height: hole.height),
            ].filter { !$0.isEmpty }
        }

        override func resetCursorRects() {
            guard let rects = pointerRects() else { return super.resetCursorRects() }
            for (rect, cursor) in rects { addCursorRect(rect, cursor: cursor) }
        }

        override func mouseMoved(with event: NSEvent) {
            if isUnderHand(event) { NSCursor.pointingHand.set() } else { super.mouseMoved(with: event) }
        }

        override func cursorUpdate(with event: NSEvent) {
            if isUnderHand(event) { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
        }

        /// Reply belongs to the text with the selection, and can reach over the text above
        /// it; a `HandArea` can be over any text.
        private func isUnderHand(_ event: NSEvent) -> Bool {
            let owner = button == nil ? window?.firstResponder as? SelectableTextView : self
            if let owner, let button = owner.button,
                button.contains(owner.convert(event.locationInWindow, from: nil))
            {
                return true
            }
            return HandArea.all.allObjects.contains {
                $0.window === window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil))
            }
        }

        // MARK: Drawing

        /// A bar down each quote's leading edge, as `MarkdownView` draws one beside a quote.
        override func draw(_ dirtyRect: NSRect) {
            if let textStorage, let layoutManager, textStorage.length > 0 {
                RichText.border.setFill()
                let all = NSRange(location: 0, length: textStorage.length)
                textStorage.enumerateAttribute(RichText.quoteBar, in: all) { value, range, _ in
                    guard value != nil else { return }
                    let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    var lines = NSRect.null
                    layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
                        lines = lines.union(used)
                    }
                    guard !lines.isNull else { return }
                    let bar = NSRect(
                        x: textContainerOrigin.x, y: textContainerOrigin.y + lines.minY, width: 3, height: lines.height)
                    NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
                }
            }
            super.draw(dirtyRect)
        }
    }

    /// What the link menu's items do.
    private final class LinkAction: NSObject {
        let url: URL
        init(url: URL) { self.url = url }
        @objc func open() { NSWorkspace.shared.open(url) }
        @objc func copyAddress() {
            NSPasteboard.general.clearContents()
            // A mail link copies as the address, as Safari's Copy Email Address does.
            let text =
                url.scheme == "mailto" ? String(url.absoluteString.dropFirst("mailto:".count)) : url.absoluteString
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    extension SelectableTextView: NSTextViewDelegate {
        /// Opens web and mail links. A Markdown link to a path names a file on the gateway, which
        /// this Mac can't open.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            if let url, let scheme = url.scheme, scheme != "file" { NSWorkspace.shared.open(url) }
            return true
        }
    }
#endif
