#if os(macOS)
    import AppKit
    import Testing

    @testable import UsualUI

    @MainActor struct FieldScrollTests {
        private let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        private let scroll = FieldScroll()

        /// A field of `lines` lines, 100 pt tall, with the anchor behind it.
        private func field(lines: Int, y: CGFloat = 0) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: "")
            field.isEditable = true
            field.stringValue = (1...lines).map { "Line \($0)" }.joined(separator: "\n")
            field.frame = NSRect(x: 0, y: y, width: 300, height: 100)
            window.contentView?.addSubview(field)
            return field
        }

        private func anchor(behind field: NSTextField) {
            let anchor = FieldScrollAnchor.AnchorView()
            anchor.scroll = scroll
            anchor.frame = field.frame
            window.contentView?.addSubview(anchor, positioned: .below, relativeTo: field)
        }

        @Test func aFieldWithMoreTextThanFitsScrollsWhileYouTypeInIt() {
            let field = field(lines: 30)
            anchor(behind: field)
            #expect(scroll.knob.geometry.maxOffset == 0)

            window.makeFirstResponder(field)
            scroll.update()
            let geometry = scroll.knob.geometry
            #expect(geometry.maxOffset > 100)
            #expect(geometry.offset == 0)

            scroll.scroll(to: geometry.maxOffset)
            #expect(scroll.knob.geometry.offset == geometry.maxOffset)

            window.makeFirstResponder(nil)
            scroll.update()
            #expect(scroll.knob.geometry.maxOffset == 0)
        }

        @Test func textThatFitsHasNothingToScroll() {
            let field = field(lines: 2)
            anchor(behind: field)
            window.makeFirstResponder(field)
            scroll.update()
            #expect(scroll.knob.geometry.maxOffset <= 1)
        }

        @Test func typingInAnotherFieldIsNotThisFieldsScroll() {
            anchor(behind: field(lines: 30))
            let other = field(lines: 30, y: 150)
            window.makeFirstResponder(other)
            scroll.update()
            #expect(scroll.knob.geometry.maxOffset == 0)
        }
    }
#endif
