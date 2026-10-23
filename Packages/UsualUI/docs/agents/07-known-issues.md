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

## Trailing toolbar items land on the leading side

- Symptom: the profile panel's close button, as a `.primaryAction` or `.automatic` toolbar item, drew on the left next to Search and New Room.
- Root cause: on macOS, `.primaryAction` is the leading edge, and with no other trailing items the toolbar packs everything to the left.
- Fix (confirmed by screenshot 2026-10-23): on macOS 26, put `ToolbarSpacer(.flexible)` before a plain `ToolbarItem`; the button then sits at the window's top right as a glass circle (`profileCloseButton` in RootView.swift).
