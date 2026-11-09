#if os(macOS)
    import AppKit
    import Testing
    import UniformTypeIdentifiers

    @testable import UsualUI

    /// A private pasteboard, so the tests never touch the clipboard.
    @MainActor struct PastedAttachmentsTests {
        private let pasteboard = NSPasteboard.withUniqueName()
        private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        @Test func aScreenshotIsAttached() {
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            pasteboard.setData(Data("tiff".utf8), forType: .tiff)
            #expect(PastedAttachments.item(on: pasteboard) == .image(png, .png))
        }

        @Test func filesCopiedInFinderAreAttachedNotTheirNames() {
            let url = URL(fileURLWithPath: "/tmp/report.pdf")
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
            pasteboard.setString("report.pdf", forType: .string)
            #expect(PastedAttachments.item(on: pasteboard) == .files([url]))
        }

        @Test func textPastesAsTextEvenWithAPictureOfIt() {
            pasteboard.clearContents()
            pasteboard.setString("Q3 revenue", forType: .string)
            pasteboard.setData(png, forType: .png)
            #expect(PastedAttachments.item(on: pasteboard) == nil)
        }

        @Test func aWebLinkPastesAsText() {
            pasteboard.clearContents()
            pasteboard.writeObjects([URL(string: "https://hermes.example.com")! as NSURL])
            #expect(PastedAttachments.item(on: pasteboard) == nil)
        }

        @Test func pastedImagesAreNamedForTheirType() async {
            let attachments = await PastedAttachments.load(.image(png, .png))
            #expect(attachments.map(\.name) == ["Image.png"])
        }

        @Test func onlyCommandVPastes() throws {
            func key(_ characters: String, _ modifiers: NSEvent.ModifierFlags, code: UInt16 = 9) throws -> NSEvent {
                try #require(
                    NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                        context: nil, characters: characters, charactersIgnoringModifiers: characters,
                        isARepeat: false, keyCode: code))
            }
            #expect(PastedAttachments.isPaste(try key("v", .command)))
            #expect(PastedAttachments.isPaste(try key("v", [.command, .capsLock])))
            #expect(!PastedAttachments.isPaste(try key("v", [.command, .shift, .option])))
            #expect(!PastedAttachments.isPaste(try key("v", [])))
            #expect(!PastedAttachments.isPaste(try key("c", .command, code: 8)))
            // A Russian layout types м on V's key.
            #expect(PastedAttachments.isPaste(try key("м", .command)))
        }
    }
#endif
