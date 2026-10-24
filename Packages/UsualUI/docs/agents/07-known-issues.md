# UsualUI: known issues

## Implemented today: source-supported limitations

No confirmed recurring failures were established during source inspection. A missing runtime check is not a proven defect. Add symptom → root cause → verified fix/workaround → prevention, with status; label untested recommendations explicitly.

## macOS 26 sidebar width can't be set (confirmed 2026-10-23)

- Symptom: a NavigationSplitView sidebar couldn't become a 78 pt rail; narrowing the window squeezed it to 140 pt with crushed rows, and a folded sidebar came back at its old narrow width and folded again ("stuck").
- Root cause: macOS 26's floating sidebar keeps a 140 pt floor and ignores `navigationSplitViewColumnWidth` minimums below it, `NSSplitView.setPosition(_:ofDividerAt:)`, and pinning the `NSSplitViewItem`'s minimum and maximum thickness. SwiftUI re-applies the saved column width.
- Fix: the Mac lays the sidebar out itself in ContactsSplitView (see components.md); iPhone keeps NavigationSplitView. Verified with screenshots at 560 and 1100 pt; dragging the edge is not verified by automation.
- Prevention: don't drive sidebar widths through NavigationSplitView or its AppKit split view on macOS 26.

## Views under the window's toolbar strip don't show

- Symptom: buttons drawn in the top strip of the window (beside the window buttons) vanished, both inside a NavigationSplitView sidebar and under a toolbar.
- Root cause: the title bar / toolbar container covers that strip.
- Fix (confirmed 2026-10-23): Search and New Room are a toolbar item (`.navigation` placement) after a clear spacer sized from the sidebar's width, with the toolbar's shared glass hidden and each button drawn by `GlassCircleButtonStyle` (`glassEffect(.regular.interactive(), in: Circle())`; `.buttonStyle(.glass)` looked flat). The toolbar also gives the window its taller title area, so the window buttons have room above them. Without a toolbar, the hidden title bar puts them 16 pt from the top.

## A long chat opened blank on iPhone (confirmed 2026-10-23)

- Symptom: opening a long agent chat (Vinioh, 39 items of long Markdown) on iPhone showed an empty pane with the scroll bar at the bottom; scrolling up about 200 pt revealed the newest message. Rooms and the Mac were fine.
- Root cause: `defaultScrollAnchor(.bottom)` and `ScrollPosition(edge: .bottom)` place the bottom by the `LazyVStack`'s estimate of rows it hasn't measured; at iPhone width the estimate ran past the real end. Swapping in a new scroll view with `.id(transcriptLoad)` didn't matter (removing it alone didn't help).
- Fix: `ConversationScroll` scrolls to an end marker view (`scrollTo(id:anchor: .bottom)`) on appear and on reload, which places the newest message exactly. Verified in the iPhone 17 Pro simulator on that chat and a room.
- Prevention: open bottom-anchored lazy lists by scrolling to a view, not to the bottom edge.

## Markdown bold and italic didn't show (confirmed 2026-10-23)

- Symptom: `**bold**` in agent replies rendered in the body weight on Mac and iPhone.
- Root cause: `Text` draws an `AttributedString`'s strong/emphasized presentation intents only while no explicit font is set, and `messageFont()` sets one.
- Fix: `MarkdownView.styled` sets a font on each bold, italic and inline-code run, at the block's size (semibold for bold; italic keeps the message weight). Verified by screenshot in the demo's Atlas chat.
- Prevention: style inline runs explicitly whenever the surrounding view sets a font.

## Unverified: Mac paste in the message box (2026-10-23)

- The message box handles ⌘V with `onPasteCommand(of: [.fileURL, .image])` so pasted files and images become attachments. Plain text paste is expected to keep working, but this was not checked by automation (no keyboard control in the test setup). If text paste breaks, drop the modifier and keep drag-and-drop and the paperclip.

## Overlays on transcript rows cover text

- Symptom: a hover bar overlaid at a message's top-right corner covered the end of the reply's first line, since replies run the full column width.
- Fix (2026-10-23): `MessageRow` lays the bar out beside the message in a fixed slot instead of overlaying it. Verified by a screenshot with the bar forced visible; real hovering wasn't automated.

## iPhone submits after a Return the key handler took (confirmed 2026-10-24)

- Symptom: with the `/` menu open, Return on the iPhone's hardware keyboard picked the row and then sent it at once.
- Root cause: on iOS a vertical `TextField` still fires `onSubmit` for a Return that `onKeyPress` returned `.handled` for (the Mac doesn't).
- Fix: `MessageBox` notes when Return picked from the menu (`pickedAt`) and ignores a submit within 0.3 s; the menus also ignore a trailing newline. Verified in the iPhone 17 Pro simulator for `/` and `@`.

## Permission callbacks crash under Swift 6 (confirmed 2026-10-24)

- Symptom: tapping the mic stopped the app at once (no crash report, no message) once speech recognition had been granted.
- Root cause: `SFSpeechRecognizer.requestAuthorization`'s closure, written inside a `@MainActor` type, was inferred main-actor isolated; the framework calls it on a background queue and the Swift 6 runtime check traps.
- Fix: mark such framework callbacks `@Sendable` (or form them in a nonisolated context). Verified in the iPhone simulator.
- Second Mac crash (same day): macOS aborts an app that requests speech recognition without `NSSpeechRecognitionUsageDescription` in its Info.plist. Xcode's `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` build setting isn't generated for macOS, so both dictation strings live in `Config/Info.plist`. Check the built plist (`plutil -p`) after adding a usage string. It kept crashing after the fix because older builds with the same bundle ID (other DerivedData folders) were still registered with LaunchServices and lacked the key; deleting them, `lsregister -u` on each and `lsregister -f` on the current build, then opening it with `open`, cleared it. Keep one Mac build of a bundle ID around when testing privacy prompts.
- Also: the iOS Simulator has no speech model, so dictation fails there with "couldn't start"; test recognition on a device or the Mac.

## Reply images showed a border wider than the picture (fixed 2026-10-24)

- Symptom: a square image in a reply sat in a rounded border that ran on to its right, as if the aspect ratio were off.
- Root cause: `.frame(maxWidth: 420, maxHeight: 360)` around a `scaledToFit` image takes the whole 420 pt even when the image is narrower, and the clip and border follow the frame.
- Fix: `MediaLoading.displaySize` sizes the image from its own pixels (at most 420 × 360 pt, no bigger than half its pixels) and the frame is that exact size. Unit-tested; the user confirmed the square image and the new bottom spacing look right on the Mac (24 October 2026).

## A reply image pushed the iPhone transcript off-screen (fixed 2026-10-24)

- Symptom: on iPhone the Ops demo reply's text and chart ran past the right edge.
- Root cause: `ReplyImage` framed images at their exact display size (up to 420 pt wide), wider than the iPhone's column, and the reply's whole column grew with it.
- Fix: `.aspectRatio(size, contentMode: .fit)` with `.frame(maxWidth: size.width)`: the same size where it fits, narrower (same shape, border still hugging) where it doesn't. Checked in the iPhone Simulator.

## Trailing toolbar items land on the leading side

- Symptom: the profile panel's close button, as a `.primaryAction` or `.automatic` toolbar item, drew on the left next to Search and New Room.
- Root cause: on macOS, `.primaryAction` is the leading edge, and with no other trailing items the toolbar packs everything to the left.
- Fix (confirmed by screenshot 2026-10-23): on macOS 26, put `ToolbarSpacer(.flexible)` before a plain `ToolbarItem`; the button then sits at the window's top right as a glass circle (`profileCloseButton` in RootView.swift).
