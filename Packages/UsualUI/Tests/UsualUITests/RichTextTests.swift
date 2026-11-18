#if os(macOS)
    import AppKit
    import Testing

    @testable import UsualUI

    @MainActor
    struct RichTextTests {
        private let reply = """
            ## Plan

            **Turbopuffer** fits best: see https://hermes.example.com.

            - Index nightly
            - Fall back after 300 ms

            > Keep the old search
            """

        @Test func aReplyIsOneTextAcrossItsBlocks() {
            let text = RichText.reply(MarkdownBlock.parse(reply), size: 15)
            #expect(
                RichText.plain(text.string)
                    == "Plan\nTurbopuffer fits best: see https://hermes.example.com.\n• Index nightly\n• Fall back after 300 ms\nKeep the old search"
            )
            let link = text.attribute(
                .link, at: (text.string as NSString).range(of: "https://").location, effectiveRange: nil)
            #expect((link as? URL)?.host == "hermes.example.com")
        }

        @Test func selectingAcrossBlocksCopiesTheWordsAsTheyRead() {
            let view = SelectableTextView()
            view.show(.reply(MarkdownBlock.parse(reply), size: 15))
            let start = (view.string as NSString).range(of: "best").location
            let end = (view.string as NSString).range(of: "nightly")
            view.setSelectedRange(NSRange(location: start, length: NSMaxRange(end) - start))
            #expect(view.selectedWords == "best: see https://hermes.example.com.\n• Index nightly")
        }

        @Test func rightClickingTheSelectionOffersAddToChat() throws {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered,
                defer: false)
            let view = SelectableTextView()
            view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            window.contentView?.addSubview(view)
            view.show(.mine("Index the docs nightly", size: 15))
            var quoted: String?
            view.quote = { quoted = $0 }
            func rightClick() throws -> NSEvent {
                try #require(
                    NSEvent.mouseEvent(
                        with: .rightMouseDown, location: view.convert(NSPoint(x: 4, y: 8), to: nil), modifierFlags: [],
                        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                        pressure: 1))
            }
            // Nothing selected: the message's own menu (React, Reply, Copy) shows instead.
            #expect(view.menu(for: try rightClick()) == nil)

            view.setSelectedRange(NSRange(location: 0, length: 5))
            let menu = try #require(view.menu(for: try rightClick()))
            #expect(menu.items.first?.title == "Add to Chat")
            #expect(menu.items.contains { $0.action == #selector(NSText.copy(_:)) })
            #expect(
                !menu.items.contains {
                    $0.action == #selector(NSText.paste(_:)) || $0.submenu != nil && $0.title == "Font"
                })
            view.addToChat(nil)
            #expect(quoted == "Index")
            #expect(view.selectedRange().length == 0)
        }

        @Test func thePointerIsAHandOverAddToChatAndAnIBeamAroundIt() throws {
            let view = SelectableTextView()
            view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            // In a window, as in a conversation: on its own its visible part has no edges.
            let window = NSWindow(
                contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView?.addSubview(view)
            #expect(view.visibleRect == view.bounds)
            // Nothing over the text: the text view's own I-beam.
            #expect(view.pointerRects() == nil)

            // Over the text's second line, and past its leading edge.
            view.button = NSRect(x: -8, y: 20, width: 130, height: 30)
            let rects = try #require(view.pointerRects())
            let hand = rects.filter { $0.cursor == .pointingHand }.map(\.rect)
            #expect(hand == [NSRect(x: 0, y: 20, width: 122, height: 30)])
            let beams = rects.filter { $0.cursor == .iBeam }.map(\.rect)
            #expect(beams.allSatisfy { !$0.intersects(hand[0]) })
            // Together they still cover the text.
            let covered = rects.reduce(0) { $0 + $1.rect.width * $1.rect.height }
            #expect(covered == view.bounds.width * view.bounds.height)

            // Above the text's first line it's off this view, which is all text again.
            view.button = NSRect(x: 40, y: -34, width: 130, height: 30)
            #expect(view.pointerRects() == nil)
        }

        @Test func thePointerIsAHandOverAButtonFloatingOverTheText() throws {
            let view = SelectableTextView()
            view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            let window = NSWindow(
                contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView?.addSubview(view)
            #expect(view.pointerRects() == nil)

            // Jump to latest, drawn over the scroll view rather than inside the text.
            let jump = HandArea(frame: NSRect(x: 184, y: 160, width: 32, height: 32))
            window.contentView?.addSubview(jump)
            let rects = try #require(view.pointerRects())
            let hand = rects.filter { $0.cursor == .pointingHand }.map(\.rect)
            #expect(hand == [view.convert(jump.bounds, from: jump)])
            let beams = rects.filter { $0.cursor == .iBeam }.map(\.rect)
            #expect(beams.allSatisfy { !$0.intersects(hand[0]) })
            let covered = rects.reduce(0) { $0 + $1.rect.width * $1.rect.height }
            #expect(covered == view.bounds.width * view.bounds.height)

            jump.removeFromSuperview()
            #expect(view.pointerRects() == nil)
        }

        @Test func aShortMessageIsAsWideAsItsWords() {
            let view = SelectableTextView()
            view.show(.mine("Hi", size: 15))
            let short = view.fittingSize(width: 560)
            #expect(short.width < 40)
            view.show(.mine(String(repeating: "word ", count: 200), size: 15))
            let long = view.fittingSize(width: 560)
            #expect(long.width <= 560)
            #expect(long.height > short.height * 5)
        }

        @Test func aLinkInATableCellIsALinkInATextView() throws {
            let markdown = """
                | Name | Notes |
                | --- | ---: |
                | Docs | see [the limits](https://docs.example.com/limits) |
                """
            guard case .table(let table) = try #require(MarkdownBlock.parse(markdown).first) else {
                Issue.record("Expected a table")
                return
            }
            let cell = table.rows[0][1]
            let view = SelectableTextView()
            view.show(.cell(cell, size: 15, isHeader: false, alignment: .trailing))
            // The text view's own links show the hand and open on a click, as in the rest of a reply.
            #expect(view.string == "see the limits")
            let at = (view.string as NSString).range(of: "limits").location
            #expect(
                (view.textStorage?.attribute(.link, at: at, effectiveRange: nil) as? URL)?.host == "docs.example.com")
            #expect(view.linkTextAttributes?[.cursor] as? NSCursor == .pointingHand)
            let style = view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            #expect(style?.alignment == .right)
        }

        @Test func aHeaderCellIsBold() throws {
            let text = RichText.cell(AttributedString("Cost"), size: 15, isHeader: true, alignment: .leading)
            let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            #expect(NSFontManager.shared.weight(of: font) > NSFontManager.shared.weight(of: .systemFont(ofSize: 15)))
        }
    }
#endif
