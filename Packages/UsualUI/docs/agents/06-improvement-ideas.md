# UsualUI: improvement ideas

## Planned/aspirational

Add only actionable observations with impact, rough effort, affected area and status (open/in-progress/done); prune or mark shipped items.

- **Time separators in a chat** (open, medium). A chat can't show "Today 2:24 PM" between messages because `TranscriptItem` has no date. It needs a timestamp from the gateway's history and live events, kept in `OfflineCache`.
- **Real Markdown tables** (open, medium). `MarkdownView` turns a table into `a · b` lines, which `tableRowsBecomeLines` pins. Wide tables need a horizontal scroll, and that fights the bubble's hugging layout.
- **One reply as several bubbles** (open, small). A long reply is one bubble. Splitting it at block boundaries would read better, and the splits have to stay put while the reply streams.
- **Sidebar collapse button on the Mac** (open, small). The sidebar narrows to the avatar rail by dragging only.
- **Reaction pills are 26 pt tall on iPhone** (open, small). `MessageRow.reactionPills` sits close under the bubble, so a larger hit area there would overlap the next message; it needs spacing decided with the transcript layout.
