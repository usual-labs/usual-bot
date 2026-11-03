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
- **macOS 26's soft scroll edge doesn't hide text under the Mac name pill:** text stays readable
  beside it, over a hairline. The Mac keeps its own fade, solid down to the pill's bottom edge.

## macOS window and sidebar

- **macOS 26's sidebar width can't be set.** Its floating sidebar keeps a 140 pt floor and ignores `navigationSplitViewColumnWidth`, `NSSplitView.setPosition` and pinned item thickness. Don't drive sidebar widths through NavigationSplitView or its AppKit split view; ContactsSplitView lays the Mac sidebar out itself. Dragging the edge wasn't verified by automation.
- **Views under the toolbar strip don't show,** because the title bar container covers that strip. Search and New Room are a `.navigation` toolbar item after a spacer sized from the sidebar, with the toolbar's shared glass hidden and each button drawn by `CircleButtonStyle`. The toolbar also gives the window buttons their room.
- **Trailing toolbar items land on the leading side.** `.primaryAction` is the leading edge on macOS. On macOS 26, put `ToolbarSpacer(.flexible)` before a plain `ToolbarItem` (`profileCloseButton`).

- **With no chat selected, the Mac sidebar sits about 200 pt in from the window's left edge,** leaving a blank strip. Seen right after sign-in and in the demo with an unknown `-selectedContact`; selecting a chat puts it back. Cause not looked into.

## Lists and text

- **Style inline runs explicitly when the view sets a font.** `Text` draws an `AttributedString`'s strong and emphasized intents only with no explicit font, so `MarkdownView.styled` sets one per run.
- **Don't overlay transcript rows.** Replies run the full column width, so an overlay covers text; `MessageRow` puts the bar in a fixed slot beside the message.
- **Size reply images from their own pixels, and let them shrink.** A `maxWidth`/`maxHeight` frame around `scaledToFit` takes the whole width, so the border runs past the picture. A fixed size pushes the iPhone column off-screen. `ReplyImage` uses `.aspectRatio(size, contentMode: .fit)` with `.frame(maxWidth: size.width)`.

- **A Mac `Menu` ignores `.buttonStyle(.clickable)`.** It's a `PrimitiveButtonStyle`, which a `.menuStyle(.button)` menu doesn't take, so AppKit draws its grey box around the label. Give a menu `.buttonStyle(.plain)` and `.clickable()`.
- **`ImageRenderer` draws `SecureField` and `Toggle` as yellow blocks,** because it can't draw controls backed by AppKit. Sizes are right, but those controls need a run of the app to be seen.
- **On iPhone, don't use `.inspector`.** A compact inspector's content lives in the presenting chat's navigation stack: its toolbar items show in the chat's bar even while closed, `.toolbarVisibility(.hidden)` hides the chat's bar, and a `NavigationStack` inside it never pushes. Emptying its content to stop that leaves a blank sheet that can't be closed. Even a panel with no toolbar breaks the chat: with the room panel as an inspector, the room's `.principal` name pill never showed, so there was no way into the panel. On iOS the profile and the room panel are pushed instead, with `navigationDestination(isPresented:)`, which needs the split view's detail wrapped in its own `NavigationStack`: the detail column alone ignores it. Inspectors stay Mac-only.
- **An iPhone `List` section header can't use `.contextMenu`:** touch and hold triggers the header's button instead. `SectionHeader` uses `Menu(content:label:primaryAction:)`, so a tap folds and touch and hold opens the menu.
- **That `Menu` shows VoiceOver its parts:** a pop-up button, an unlabelled button and the label's image ("Go Down" for `chevron.down`). `accessibilityHidden` and `accessibilityElement(children: .ignore)` inside the label didn't change that (iOS 27 Simulator); `accessibilityRepresentation` on the menu, with its items as `accessibilityActions`, made one heading button. VoiceOver itself wasn't run, only the accessibility tree.

## Message actions

- **A Mac menu's palette drops buttons without an image.** A `.palette` `ControlGroup` in a Mac context menu showed only the `+`, not the emoji, so the Mac menu puts reactions in a React submenu; iPhone keeps the palette.
- **Accessibility modifiers inside a `.contain` group reach each element in it** (checked on the Mac through AX). `MessageRow` puts its actions on the message's content, so every paragraph carries Reply, Copy and React. On the group itself they'd belong to the container, which VoiceOver on iPhone doesn't focus.
- **Unverified on iPhone:** the 44 pt hit areas from `touchTarget` (negative padding, so they spill past the control; a scroll view's edge may still clip them), the reaction sheet opened from the long-press menu, and whether VoiceOver reads a message group's author label on the way in.

## Message box

- **iOS fires `onSubmit` for a Return `onKeyPress` handled.** `MessageBox` notes when Return picked from a menu (`pickedAt`) and ignores a submit within 0.3 s.
- **Replacing `text` keeps the old selection.** Go through `MessageBox.replaceText(with:)` so the cursor lands at the end.
- **Moving a view between stacks resets it.** The field would lose focus and `+` would drop an open picker. `ComposerLayout` repositions the same subviews; keep views that hold focus or presentation state in one place in the hierarchy.
- **The bottom safe area doesn't separate the keyboard from the home indicator.** In the iOS 26.5 Simulator, readers ignoring `.container` and `.keyboard` both report 34 pt with the keyboard down and 335 pt up. `ChatBars` treats 50 pt or less as the home indicator; keep that threshold above 34 pt and below any keyboard height.
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
