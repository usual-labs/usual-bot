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
    }
#endif
