# UsualUI: known issues

Record a new issue as symptom → root cause → verified fix or workaround → prevention, with status, and label untested recommendations. Once fixed, keep only the trap and how to avoid it.

## Conversation scrolling

- **Lazy transcript heights and competing scroll owners can leave blank space.** The old
  `LazyVStack`, size-change bottom anchor and geometry callbacks could disagree after a rewrap,
  scroll or app switch; a 500 ms settling timer only hid some occurrences. A long fake transcript
  also triggered a SwiftUI `ForEachState` / `LazyScrollable` assertion through accessibility.
  Chats and rooms now measure loaded messages in a `VStack`. One policy follows the end, leaves
  hand scrolling alone and clamps out-of-bounds positions once the gesture ends or the app returns.
  Do not restore estimated bounds or a second size-change anchor without testing long, uneven
  histories, a running reply and reading older messages. `--demo-long-chat` supplies that fixture.
  Group accessibility per message, not around the whole transcript, so Mac accessibility can
  expose the messages without traversing one enormous group.
- **A conversation must only move up.** Following the end, anything that leaves the bottom pulls
  everything above it down. A real turn moved your message down 40 pt four times: the "Thinking…"
  row left with each tool call and came back after it, and the to-do and helper lines vanished
  when the turn ended. Now the newest tool line carries the working status instead of a row of its
  own, a finished turn keeps its lines as a `.progress` item, and `GrowsOnly` keeps any other space
  that leaves (an answered card, a background helper) until something fills it, the reader scrolls
  it out of sight, or an undo, reload or width change lets it go. Measured on a real gateway, frame
  by frame: up only. A new row that comes and goes at the end needs the same care; `GrowsOnly` hides
  the bounce but leaves a gap. The demo can't answer a card, so that case is covered by
  `GrowsOnlyTests`, not seen.
- **The non-lazy transcript costs every built message on every layout.** A 165-message demo chat
  took about 800 ms to open and 37 ms per resize step even in Release. `TranscriptWindow` builds the
  newest page and adds a page when the reader nears the top; `ConversationScrollState` then moves
  the offset by the growth, even mid-gesture, so the same message stays put. A search jump keeps
  its target in the window. The offscreen harness that measured this hosted `TranscriptView` in an
  `NSHostingView` and timed `layoutSubtreeIfNeeded()`; the continuity of a reveal during a real
  trackpad scroll was seen once, not frame by frame.
- **The Mac's grouped `Form` builds every row.** 120 switch rows took about 450 ms, against 60 ms in
  a `LazyVStack` inside the section, so the Skills page lays its rows out itself on the Mac.
  iPhone's form is lazy already.
- **Judge speed on a Release build.** A Debug app (`-Onone`, the previews debug dylib) used 25–38%
  CPU to animate one working avatar that Release draws for nothing, and resized about six times
  slower. Profile and dogfood Release.
- **Selectable text costs an AppKit view per `Text` on the Mac,** and SwiftUI hit-tests them on
  every pointer move: about half that work in a long chat. `MarkdownView` joins a reply's
  paragraphs and headings into one `Text`. `Text` ignores `NSParagraphStyle` spacing and indents,
  so the gaps are blank lines in a 2 pt (5 pt before a heading) font, tuned against
  `messageFont()`'s 4 pt `lineSpacing`: change either and compare a reply before and after.
  Lists, quotes and code stay separate views.
- **Anything that asks a scroll view its size measures every message in it.** `safeAreaBar`
  asks for the conversation's minimum on each update, and so does the window for its minimum size:
  about a fifth of switching chats. `ConversationScroll` sits in `TakesOfferedSize`, which answers
  with the space offered and measures only for an ideal size.
- **`onHover` on a message hit-tests the text inside it on every pointer move.** Crossing a long
  chat kept the app busy for up to half a second at a time. `MessageRow` follows the pointer with
  an AppKit tracking area (`PointerTracking`) instead.
- **Build `NSRegularExpression`s once.** Compiling the image-path pattern per paragraph was most of
  the Markdown parsing cost.

- **`ScrollPosition.scrollTo(id:anchor:)` left a search jump at the top on iOS 18.4** (Simulator),
  under the navigation bar, whatever the anchor. `ConversationScroll` jumps with a
  `ScrollViewReader`, which centres on both platforms; the scroll policy stays on `ScrollPosition`.
- **The two owners race when history and a jump arrive together** (a result found on the
  gateway). The taller content reaches `onScrollGeometryChange` before the jump, so the policy
  queues a move to the end, and on iOS 27 that move landed after the reader's `scrollTo` and won.
  The order of the `reload` and `jump` `onChange` handlers isn't fixed either. So the policy skips
  the end for the load a jump came with, and a jump scrolls again after the next layout.
- **A load changes the same counts news and sending do.** History for a search result adds items and
  your messages at once, so the jump-to-latest dot and "you sent, follow the end" compare counts only
  within one `transcriptLoad`. Rooms have no load count, so a page of older room history would read
  as sending.
- **macOS 26's soft scroll edge doesn't hide text beside the Mac's name:** it stays readable, over
  a hairline. The Mac's top bar uses the hard edge, which needs the bar as a `safeAreaBar`, not a
  `safeAreaInset`. In dark mode the hard edge is translucent: a white chart under it still shows
  faintly.

## macOS window and sidebar

- **macOS 26's sidebar width can't be set.** Its floating sidebar keeps a 140 pt floor and ignores `navigationSplitViewColumnWidth`, `NSSplitView.setPosition` and pinned item thickness. Don't drive sidebar widths through NavigationSplitView or its AppKit split view; ContactsSplitView lays the Mac sidebar out itself. Dragging the edge wasn't verified by automation.
- **Views under the toolbar strip don't show,** because the title bar container covers that strip. So the sidebar's toggle, Search and New are a `.navigation` toolbar group in the toolbar's own glass, after a clear `.navigation` item as wide as the list leaves (`toolbarGroupWidth`, measured from screenshots); only that clear item hides its shared glass. The toolbar also gives the window buttons their room.
- **The chat's name and buttons can't be window toolbar items.** Tried on macOS 26: a `.principal` item centres on the window, not on the chat beside ContactsSplitView's sidebar (140 pt off with the full list), the scroll edge doesn't reach under it, and a glass button there gets the toolbar's glass as well as its own. They float in the chat's own `safeAreaBar` instead.
- **Trailing toolbar items land on the leading side.** `.primaryAction` is the leading edge on macOS. On macOS 26, put `ToolbarSpacer(.flexible)` before a plain `ToolbarItem`.

- **The Mac's profile and room panels aren't `.inspector`s.** A Mac inspector is an AppKit split view: it slides on its own even-speed curve, which an app can't change, lays the chat out again on every frame, and in a long chat froze for about 100 ms mid-slide. `sidePanel` puts the panel in an `HStack` beside the chat and slides it in with a SwiftUI animation, so the chat is laid out once at its new width. Measured in the demo's long chat: 21 frames with no gap over 22 ms, against the inspector's 6 to 9 larger steps. Toggles were driven over accessibility in a window that wasn't key; a key window and a long real chat weren't measured.
- **Conversations draw their own scroll knob on the Mac (`ScrollKnob`).** With a mouse connected, macOS shows the wide, bright legacy scroller, and SwiftUI can't restyle it. `.scrollIndicators(.hidden)` still shows it then; `.never` hides it. The scroll view's frame already stops at the bars pinned over the chat, so its `containerSize` is the visible height and the knob's track is the whole frame: subtracting `contentInsets` as well shortened the track by both bars. Clicking the track to page and the system's scroll-bar setting aren't honoured. Other scroll views keep the system's.
- **A Mac button that moves itself must act after the click.** The chat's name pill opens the side panel, which moves the pill. Toggled in the button's action, the pill jumped to its new place while the rest of the chat slid: the release of the press lands in the same update and turns animation off for the button's label. Plain glass instead of interactive glass didn't help. `NamePill` toggles on the next run-loop turn instead. A press over accessibility never set the pressed state and slid either way, so only a real mouse click shows this.
- **Keep the window wide enough for the open panel.** Opened in a narrow window, an inspector pushed the sidebar and the chat off both sides. `OpenPanelWidth` carries the open panel's width up to `RootView`, which counts it in the window's minimum width and folds the sidebar to the rail first. A profile needs 390 pt: its grouped form with five tabs is that wide at the least, and narrower it spilled over the chat (at 320) or was cut off at both sides (at 370).
- **The chat can need more than its 360 pt.** In the demo, Forge's approval card holds the chat at about 428 pt, so a window at its minimum still spills that chat off both sides. Not looked into.
- **With no chat selected, the Mac sidebar sits about 200 pt in from the window's left edge,** leaving a blank strip. Seen right after sign-in and in the demo with an unknown `-selectedContact`; selecting a chat puts it back. Cause not looked into.
- **A Mac sheet's bar draws no `.navigation` item.** `SheetForm` put Back there: it was invisible, and its Esc with it, so a routine's run had no way out. Back now takes the bottom-left slot (`.destructiveAction`); a sheet using `extra` and `back` together would share it.
- **SwiftUI won't quit while a window shows a sheet,** and the app delegate's `applicationShouldTerminate` isn't asked. Closing the sheet's `NSWindow` doesn't help: SwiftUI puts it back while its state says it's open. `UsualBotCommands.quit()` closes the sheets, calls `terminate`, and exits half a second later if that was refused. Quitting from the Dock or at logout still goes through `terminate` alone and is unverified with a sheet open.

## Lists and text

- **`.font(.system(size:))` ignores Dynamic Type,** and `Font.custom(_:size:relativeTo:)` doesn't help with the system font. Use `scaledFont`, and don't scale a size twice: `messageTextSize` and `composerButtonSize` arrive scaled. A `Spacer` in an `AnyLayout` that switches from a row to a column at accessibility sizes stretches the column; add it only in the row.
- **A scaled glyph overflows a fixed frame.** At the largest size a 13 pt symbol is about 44 pt, so a symbol in a fixed 28 pt circle keeps a fixed size, or the circle scales with it through a capped `@ScaledMetric`.
- **Style inline runs explicitly when the view sets a font.** `Text` draws an `AttributedString`'s strong and emphasized intents only with no explicit font, so `MarkdownView.styled` sets one per run.
- **Don't overlay transcript rows.** Replies run the full column width, so an overlay covers text; `MessageRow` puts the bar in a fixed slot beside the message.
- **Size reply images from their own pixels, and let them shrink.** A `maxWidth`/`maxHeight` frame around `scaledToFit` takes the whole width, so the border runs past the picture. A fixed size pushes the iPhone column off-screen. `ReplyImage` uses `.aspectRatio(size, contentMode: .fit)` with `.frame(maxWidth: size.width)`.

- **A Mac `Menu` ignores `.buttonStyle(.clickable)`, `.clickable(_:)` and `.inkProminent`.** They're `PrimitiveButtonStyle`s, which a `.menuStyle(.button)` menu doesn't take, so AppKit draws its grey box around the label. A system style works, but it flattens the label to a title and an image: the gateway button's status dot and spacer were lost under `.borderless`. An icon or text menu takes a system style; a menu with a drawn label keeps `.buttonStyle(.plain)` and `.clickable()`. So a menu gets its pointing hand from `.clickable()` on the menu itself, and a style set on a container that holds a menu (the narrow sidebar rail, the model menus) stays a system one.
- **A Mac window that isn't key draws prominent buttons unfilled,** in their label colour. Screenshots of a demo opened in the background (`open -g`) don't show which button is prominent.
- **Unverified: Return and Esc in Mac sheets.** AX reports no default or cancel button for a SwiftUI sheet, so which toolbar button each key presses was checked only by reading `SheetForm`, not by pressing them.
- **A prominent button's label is white,** and dark mode's ink tint is near white, so `.borderedProminent` and `.glassProminent` buttons read white on white (seen on iPhone). Use `.inkProminent` / `.inkGlassProminent`: on iPhone they set the label to `Theme.primaryInk` (a `.foregroundStyle` on the button reaches the label), and on the Mac they fill dark mode with `Theme.prominent`, a grey white reads on. For the same reason switches take `.toggleStyle(.systemSwitch)`, the system's own on colour: under the ink tint the white knob vanished into a near-white track, and on and off looked alike.
- **Unverified: where the pointing hand starts over a Form row.** `pointerStyle` can't be probed from automation: events sent to a window move neither the cursor nor `onHover`. Pickers and switches in grouped Forms carry `.clickable()` on the whole control, which may take in its label.
- **`ImageRenderer` draws `SecureField` and `Toggle` as yellow blocks,** because it can't draw controls backed by AppKit. Sizes are right, but those controls need a run of the app to be seen.
- **On iPhone, don't use `.inspector`.** A compact inspector's content lives in the presenting chat's navigation stack: its toolbar items show in the chat's bar even while closed, `.toolbarVisibility(.hidden)` hides the chat's bar, and a `NavigationStack` inside it never pushes. Emptying its content to stop that leaves a blank sheet that can't be closed. Even a panel with no toolbar breaks the chat: with the room panel as an inspector, the room's `.principal` name pill never showed, so there was no way into the panel. On iOS the profile and the room panel are pushed instead, with `navigationDestination(isPresented:)`, which needs the split view's detail wrapped in its own `NavigationStack`: the detail column alone ignores it. The Mac doesn't use inspectors either (see the side panels above).
- **An iPhone `List` section header can't use `.contextMenu`:** touch and hold triggers the header's button instead. `SectionHeader` uses `Menu(content:label:primaryAction:)`, so a tap folds and touch and hold opens the menu.
- **That `Menu` shows VoiceOver its parts:** a pop-up button, an unlabelled button and the label's image ("Go Down" for `chevron.down`). `accessibilityHidden` and `accessibilityElement(children: .ignore)` inside the label didn't change that (iOS 27 Simulator); `accessibilityRepresentation` on the menu, with its items as `accessibilityActions`, made one heading button. VoiceOver itself wasn't run, only the accessibility tree.

## Message actions

- **macOS 26 swaps the face symbols with the appearance.** `face.smiling` is an outline in light mode and filled in dark mode; `face.smiling.inverse` is the opposite. `MessageRow.reactSymbol` picks by `colorScheme` so React stays an outline. Seen in the app and in `ImageRenderer`; not checked on iPhone, where only the long-press menu shows it.
- **A Mac menu's palette drops buttons without an image.** A `.palette` `ControlGroup` in a Mac context menu showed only the `+`, not the emoji, so the Mac menu puts reactions in a React submenu; iPhone keeps the palette.
- **Accessibility modifiers inside a `.contain` group reach each element in it** (checked on the Mac through AX). `MessageRow` puts its actions on the message's content, so every paragraph carries Reply, Copy and React. On the group itself they'd belong to the container, which VoiceOver on iPhone doesn't focus.
- **Unverified on iPhone:** the 44 pt hit areas from `touchTarget` (negative padding, so they spill past the control; a scroll view's edge may still clip them), the reaction sheet opened from the long-press menu, and whether VoiceOver reads a message group's author label on the way in.

## Message box

- **iOS fires `onSubmit` for a Return `onKeyPress` handled.** `MessageBox` notes when Return picked from a menu (`pickedAt`) and ignores a submit within 0.3 s.
- **Replacing `text` keeps the old selection.** Go through `MessageBox.replaceText(with:)` so the cursor lands at the end.
- **Moving a view between stacks resets it.** The field would lose focus and `+` would drop an open picker. `ComposerLayout` repositions the same subviews; keep views that hold focus or presentation state in one place in the hierarchy.
- **The bottom safe area doesn't separate the keyboard from the home indicator.** In the iOS 26.5 Simulator, readers ignoring `.container` and `.keyboard` both report 34 pt with the keyboard down and 335 pt up. `ChatBars` reads the window's own bottom inset (UIKit), which leaves the keyboard out, and takes the rest as the keyboard. Unverified: a phone without a home indicator, and the eased margin during a swipe-down. The device tool's drags can't reach into the keyboard, so a swipe can't be scripted in the Simulator.
- **The iPhone message box opens on the keyboard, not on focus.** Opening on focus grew the box before the keys rose, a beat apart on a phone. `keyboardUp` from `ChatBars` changes in the keyboard's own animation, so the box opens and closes in it. Unverified: the 0.6 s fallback for a hardware keyboard, which raises no keys. The headless Simulator always raises them.
- **The Mac draws Send grey in a window you aren't at.** macOS greys tinted glass while its window
  isn't key: `.glassProminent`, and `.glassEffect(.regular.tint(_:))` too; `appearsActive` and
  `controlActiveState` set to active didn't change it. Automation launches the demo in the
  background, so screenshots show it grey. Unverified: the Bot's colour in a key window.
- **Unverified: ⌘. for Stop.** A hidden button in `MessageBox`, as ⌘K is in `RootView`; automation couldn't press it without taking the keyboard.
- **Unverified: Mac paste.** ⌘V uses `onPasteCommand(of: [.fileURL, .image])`. Plain text paste wasn't checked by automation. If it breaks, drop the modifier and keep drag-and-drop and the paperclip.
- **Unverified: the iPhone sign-in sheet closes itself.** `SignInPage` cancels the task running `WebAuthenticationSession.authenticate` once Hermes says the app connected, relying on task cancellation to dismiss the sheet. Not yet run on a device or Simulator; if the sheet stays, keep an `ASWebAuthenticationSession` and call `cancel()` instead.
- **The demo's Connect card and Apps page don't share state.** Connecting Notion in Scribe's chat leaves it unconnected on the Apps page; each fakes its own result.
- **Demo mode can't show a thinking level change.** `ChatThread.setReasoning` needs a live session, so the slider snaps back there.

## Audio and video

- **One `AVPlayer` for the app (`MediaPlayback.shared`).** Views compare its key, so reading
  `elapsed` outside the playing view would redraw every player ten times a second. A finished file
  stays loaded at its start, so a full-screen video isn't pulled out from under AVKit.
- **AVPlayerView exposed nothing to the accessibility tree** inline in a chat (macOS 27, checked
  with AX queries, not VoiceOver itself), so on the Mac the playing video is one element with
  Play, Pause and Play from the start. Its full-screen button shows on hover only; unverified with
  VoiceOver.
- **The panel is hidden, not removed,** so its views never disappear: `QuickPanel.close()` stops
  what played there through `QuickMessageView.panelClosed()`.
- **Unverified:** Ogg/Opus and WebM in AVFoundation (they show "can't play" and Share if not), iPhone
  inline playback and full screen, and the silent switch with the `.playback` session.

## Voice and permissions

- **Permission callbacks crash under Swift 6.** A framework closure written in a `@MainActor` type is inferred main-actor isolated and traps on a background queue. Mark such callbacks `@Sendable` or form them in a nonisolated context.
- **macOS aborts an app that requests speech recognition without `NSSpeechRecognitionUsageDescription`.** Xcode doesn't generate that key for macOS, so both dictation strings live in `Config/Info.plist`. Check the built plist with `plutil -p`.
- **Keep one Mac build of a bundle ID when testing privacy prompts.** Older builds in other DerivedData folders stay registered with LaunchServices. Delete them, `lsregister -u` each, `lsregister -f` the current build, and open it with `open`.
- **The iOS Simulator has no speech model,** so dictation fails there. Test recognition on a device or the Mac.
- **Echo cancellation can fail to start on the Mac** (`AUVoiceProcessor` -10875, dependent on audio devices). `CallAudio.start()` retries without voice processing and the call takes turns. The `call` log category says which mode a call got.
- **WebRTC runs through WebKit, by design,** because Apple ships no public WebRTC API. The web view must be in the hierarchy (`LiveCallHost`), the page needs a secure origin for `getUserMedia` (an `https://…invalid/` base URL, nothing fetched), autoplay needs `mediaTypesRequiringUserActionForPlayback = []` plus inline playback on iPhone, and the microphone needs TCC plus the `WKUIDelegate` grant.
- **macOS refuses notifications from ad-hoc signed builds.** `requestAuthorization` fails at once for a `CODE_SIGNING_ALLOWED=NO` build. To test them, copy the app out of DerivedData and `codesign --force --deep --sign "Apple Development: …"` it, with no entitlements so it keeps the same defaults and sign-in. That copy reads the Keychain as a new app, so macOS may ask.
- **A launch argument pins its default.** `-selectedContact forge` overrides `@AppStorage` for the whole run, so selecting another chat appears to do nothing. Leave it out to test anything that changes the selection.
- **`usualbot://` links need `handlesExternalEvents` on the view as well as the scene.** With only the scene's, every link opens another window. With several builds registered, `open` may launch any of them: name the app.
- **A Mac `TextField` sets its binding when it takes focus,** with the value it already has. A custom binding that marks a field as edited on set (the template form's `touched`) must compare first, or a sheet's first field looks edited as soon as it opens.
