# UsualUI: known issues

Record a new issue as symptom → root cause → verified fix or workaround → prevention, with status, and label untested recommendations. Once fixed, keep only the trap and how to avoid it.

## macOS window and sidebar

- **macOS 26's sidebar width can't be set.** Its floating sidebar keeps a 140 pt floor and ignores `navigationSplitViewColumnWidth`, `NSSplitView.setPosition` and pinned item thickness. Don't drive sidebar widths through NavigationSplitView or its AppKit split view; ContactsSplitView lays the Mac sidebar out itself. Dragging the edge wasn't verified by automation.
- **Views under the toolbar strip don't show,** because the title bar container covers that strip. Search and New Room are a `.navigation` toolbar item after a spacer sized from the sidebar, with the toolbar's shared glass hidden and each button drawn by `CircleButtonStyle`. The toolbar also gives the window buttons their room.
- **Trailing toolbar items land on the leading side.** `.primaryAction` is the leading edge on macOS. On macOS 26, put `ToolbarSpacer(.flexible)` before a plain `ToolbarItem` (`profileCloseButton`).

- **With no chat selected, the Mac sidebar sits about 200 pt in from the window's left edge,** leaving a blank strip. Seen right after sign-in and in the demo with an unknown `-selectedContact`; selecting a chat puts it back. Cause not looked into.

## Lists and text

- **Open bottom-anchored lazy lists by scrolling to a view,** not the bottom edge. `defaultScrollAnchor(.bottom)` and `ScrollPosition(edge: .bottom)` use the `LazyVStack`'s estimate, which opened long iPhone chats blank. `ConversationScroll` scrolls to an end marker.
- **Style inline runs explicitly when the view sets a font.** `Text` draws an `AttributedString`'s strong and emphasized intents only with no explicit font, so `MarkdownView.styled` sets one per run.
- **Don't overlay transcript rows.** Replies run the full column width, so an overlay covers text; `MessageRow` puts the bar in a fixed slot beside the message.
- **Size reply images from their own pixels, and let them shrink.** A `maxWidth`/`maxHeight` frame around `scaledToFit` takes the whole width, so the border runs past the picture. A fixed size pushes the iPhone column off-screen. `ReplyImage` uses `.aspectRatio(size, contentMode: .fit)` with `.frame(maxWidth: size.width)`.

- **Keep a conversation at its end with `ScrollPosition.scrollTo(y:)`, not the end marker.** `defaultScrollAnchor(.bottom)` can't hold a column that started shorter than its window, and after a scroll to the marker it stops holding at all: new messages, cards and the background bar landed under the message box. Scrolling to the marker again doesn't help, because it's stale until the new row is laid out and pulled the view back 123 pt. `ConversationScroll` follows the measured end until you scroll by hand. Whether you left the end comes from scroll phases, since lazy estimates move it while nobody scrolls. `scrollTo(y:)` counts from the content's top, `contentOffset` from behind the top bar, and `containerSize` leaves the bars out. The demo can't show this: its cards exist from the start, so check a card arriving on a real gateway.
- **`ImageRenderer` draws `SecureField` and `Toggle` as yellow blocks,** because it can't draw controls backed by AppKit. Sizes are right, but those controls need a run of the app to be seen.

## Message box

- **iOS fires `onSubmit` for a Return `onKeyPress` handled.** `MessageBox` notes when Return picked from a menu (`pickedAt`) and ignores a submit within 0.3 s.
- **Replacing `text` keeps the old selection.** Go through `MessageBox.replaceText(with:)` so the cursor lands at the end.
- **Moving a view between stacks resets it.** The field would lose focus and `+` would drop an open picker. `ComposerLayout` repositions the same subviews; keep views that hold focus or presentation state in one place in the hierarchy.
- **The bottom safe area doesn't separate the keyboard from the home indicator.** In the iOS 26.5 Simulator, readers ignoring `.container` and `.keyboard` both report 34 pt with the keyboard down and 335 pt up. `ChatBars` treats 50 pt or less as the home indicator; keep that threshold above 34 pt and below any keyboard height.
- **Unverified: Mac paste.** ⌘V uses `onPasteCommand(of: [.fileURL, .image])`. Plain text paste wasn't checked by automation. If it breaks, drop the modifier and keep drag-and-drop and the paperclip.
- **Demo mode can't show a thinking level change.** `ChatThread.setReasoning` needs a live session, so the slider snaps back there.

## Voice and permissions

- **Permission callbacks crash under Swift 6.** A framework closure written in a `@MainActor` type is inferred main-actor isolated and traps on a background queue. Mark such callbacks `@Sendable` or form them in a nonisolated context.
- **macOS aborts an app that requests speech recognition without `NSSpeechRecognitionUsageDescription`.** Xcode doesn't generate that key for macOS, so both dictation strings live in `Config/Info.plist`. Check the built plist with `plutil -p`.
- **Keep one Mac build of a bundle ID when testing privacy prompts.** Older builds in other DerivedData folders stay registered with LaunchServices. Delete them, `lsregister -u` each, `lsregister -f` the current build, and open it with `open`.
- **The iOS Simulator has no speech model,** so dictation fails there. Test recognition on a device or the Mac.
- **Echo cancellation can fail to start on the Mac** (`AUVoiceProcessor` -10875, dependent on audio devices). `CallAudio.start()` retries without voice processing and the call takes turns. The `call` log category says which mode a call got.
- **WebRTC runs through WebKit, by design,** because Apple ships no public WebRTC API. The web view must be in the hierarchy (`LiveCallHost`), the page needs a secure origin for `getUserMedia` (an `https://…invalid/` base URL, nothing fetched), autoplay needs `mediaTypesRequiringUserActionForPlayback = []` plus inline playback on iPhone, and the microphone needs TCC plus the `WKUIDelegate` grant.
