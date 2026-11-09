#if os(macOS)
    import AppKit
    import SwiftUI

    /// A message's words on the Mac, in one AppKit text view: a drag selects across paragraphs,
    /// headings, list items and quotes, as in a web page. With words selected, Add to Chat (its
    /// button, the right-click menu or ⌘L) quotes them in your next message.
    struct MessageText: View {
        let content: MessageTextContent
        @Environment(\.quoteSelection) private var quoteSelection
        @State private var selection: SelectedWords?

        var body: some View {
            MessageTextView(content: content, quote: quoteSelection) { selection = $0 }
                .overlay {
                    if let selection, quoteSelection != nil {
                        AddToChatButton(action: selection.add)
                            // Centred over where the drag ended, just above the selection's first line,
                            // and not far past the text's leading edge.
                            .position(
                                x: max(selection.anchor.x, AddToChatButton.width / 2 - 8),
                                y: selection.anchor.y - AddToChatButton.height / 2 - 4
                            )
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: selection)
        }
    }

    /// Words selected in a message, and where to show Add to Chat: the selection's top, in the text
    /// view's coordinates.
    struct SelectedWords: Equatable {
        let text: String
        let anchor: CGPoint
        /// Adds them to the chat and clears the selection.
        let add: () -> Void

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text && lhs.anchor == rhs.anchor }
    }

    /// A small pill over a selection, as in a coding agent's chat.
    private struct AddToChatButton: View {
        let action: () -> Void
        /// About how wide it is, to keep it in the message.
        static let width: CGFloat = 130
        static let height: CGFloat = 30

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Text("Add to Chat")
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
                .frame(height: Self.height)
                .contentShape(Capsule())
            }
            .buttonStyle(.clickable)
            .glassEffect(.regular, in: Capsule())
            .fixedSize()
            .help("Quote the selected words in your next message")
            .accessibilityLabel(Text("Add to Chat"))
        }
    }

    private struct MessageTextView: NSViewRepresentable {
        let content: MessageTextContent
        let quote: ((String) -> Void)?
        let selected: (SelectedWords?) -> Void

        func makeNSView(context: Context) -> SelectableTextView {
            SelectableTextView()
        }

        func updateNSView(_ view: SelectableTextView, context: Context) {
            view.quote = quote
            view.selected = selected
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
        var quote: ((String) -> Void)?
        var selected: (SelectedWords?) -> Void = { _ in }
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
        /// box, lets go of it.
        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { setSelectedRange(NSRange(location: selectedRange().location, length: 0)) }
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
            let range = selectedRange()
            var words: SelectedWords?
            if range.length > 0, let layoutManager, let textContainer {
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                // Over where the drag ended; from the keyboard, over the selection's middle.
                var x = bounds.midX
                if let event = NSApp?.currentEvent, event.window === window,
                    [.leftMouseUp, .leftMouseDragged, .leftMouseDown].contains(event.type)
                {
                    x = convert(event.locationInWindow, from: nil).x
                }
                words = SelectedWords(
                    text: selectedWords, anchor: CGPoint(x: min(max(x, 0), self.bounds.width), y: bounds.minY),
                    add: { [weak self] in self?.addToChat(nil) })
            }
            // Later: this can run while SwiftUI updates the view, which mustn't change its state.
            let selected = selected
            Task { @MainActor in selected(words) }
        }

        /// Quotes the selection, then lets go of it: it's in the message box now.
        @objc func addToChat(_ sender: Any?) {
            let range = selectedRange()
            guard range.length > 0, let quote else { return }
            quote(selectedWords)
            setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers?.lowercased() == "l", quote != nil,
                window?.firstResponder === self, selectedRange().length > 0
            {
                addToChat(nil)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        /// Right-clicking the selection offers Add to Chat and the text's own commands; anywhere
        /// else, the message's menu (React, Reply, Copy).
        override func menu(for event: NSEvent) -> NSMenu? {
            let range = selectedRange()
            let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            guard range.length > 0, index >= range.location, index <= NSMaxRange(range),
                let menu = super.menu(for: event)
            else { return nil }
            Self.dropEditing(from: menu)
            if quote != nil {
                let item = NSMenuItem(
                    title: String(localized: "Add to Chat"), action: #selector(addToChat(_:)), keyEquivalent: "l")
                item.keyEquivalentModifierMask = .command
                item.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: nil)
                item.target = self
                menu.insertItem(item, at: 0)
                menu.insertItem(.separator(), at: 1)
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
