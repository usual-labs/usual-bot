# UsualUI: known issues

## Implemented today: source-supported limitations

No confirmed recurring failures were established during source inspection. A missing runtime check is not a proven defect. Add symptom → root cause → verified fix/workaround → prevention, with status; label untested recommendations explicitly.

## macOS 26 sidebar width can't be set (confirmed 2026-10-23)

- Symptom: a NavigationSplitView sidebar couldn't become a 78 pt rail; narrowing the window squeezed it to 140 pt with crushed rows, and a folded sidebar came back at its old narrow width and folded again ("stuck").
- Root cause: macOS 26's floating sidebar keeps a 140 pt floor and ignores `navigationSplitViewColumnWidth` minimums below it, `NSSplitView.setPosition(_:ofDividerAt:)`, and pinning the `NSSplitViewItem`'s minimum and maximum thickness. SwiftUI re-applies the saved column width.
- Fix: the Mac lays the sidebar out itself in ContactsSplitView (see components.md); iPhone keeps NavigationSplitView. Verified with screenshots at 560 and 1100 pt; dragging the edge is not verified by automation.
- Prevention: don't drive sidebar widths through NavigationSplitView or its AppKit split view on macOS 26.

## Views in the hidden title bar strip of a NavigationSplitView sidebar don't show

- Symptom: a button placed in the top 28 pt of the sidebar (beside the window buttons) didn't draw.
- Workaround: in the app's own sidebar layout (no NavigationSplitView) the top row draws there; inside NavigationSplitView, use toolbar items instead.

