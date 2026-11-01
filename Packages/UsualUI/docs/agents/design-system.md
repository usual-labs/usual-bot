# UsualUI: design system

## Implemented today

`Theme.swift` centralizes colours: neutral surfaces, ink, border, selection and the agent palette. `window` sits behind `pane`, a reply sits on `bubble`, and `surface` is anything floating. Glass is gone on purpose: `floatingSurface` is solid, so bubbles and cards keep their contrast over whatever scrolls behind them.

**Text.** Chat text (replies, your bubbles, quotes, list items) gets its typography from `messageFont()`: `Theme.messageSize` (15 pt on the Mac, 16 pt on iPhone) with 4 pt line spacing, regular weight in both modes. Markdown headings are that size plus 5, 2 or 0. Markdown blocks sit 10 pt apart so paragraphs stay distinct from the line spacing. Don't add per-view `.lineSpacing`.

**Colour of a chat.** `Contact.accent` is the Bot's picked or palette colour, passed through `readableUnderWhite`, because white text sits on it in your bubbles and in the voice and send buttons. `chatContact` carries the contact to views inside a chat. It's nil in a room, where there's no single colour, so those fall back to `Theme.userBubble` and `Theme.primary`.

**Shapes.** Replies are `AgentBubble`: 18 pt radius, with joined corners at 6 pt where a message from the same sender touches. `UpToWidth`, not `.frame(maxWidth:)`, keeps a bubble hugging short text, since `maxWidth` fills what it's offered. `MarkdownView` must not set a width of its own for the same reason. Anything that asks you for something uses `cardSurface()`. Keep labels and actionable buttons there; don't turn approval or question cards into decorative status text.

**Motion.** New items use `AnyTransition.rise` (your message) or `.settle` (everything else); a reply taking over from its streaming draft uses `.identity`, so it doesn't flicker. `ConversationScroll` animates only when `arrival` changes in a chat that has finished loading, otherwise opening a chat replays every message. Each chat and room's transcript is keyed with `.id(contact.id)`: item IDs restart at 0 in every chat, so without it a switch animates one chat's messages into the next. `WorkingRow`, `ShimmerText` and `Breathing` all stand still under Reduce Motion, and any new motion must too.

Native SwiftUI layout and NavigationSplitView provide platform adaptation.

Source anchors: `Package.swift`, `Sources/UsualUI/RootView.swift`, `Sources/UsualUI/Theme/Theme.swift`, `Sources/UsualUI/Thread/Bubbles.swift`, `Sources/UsualUI/Thread/Composer.swift`, `Sources/UsualUI/Thread/ApprovalCard.swift`, `Sources/UsualUI/Room/RoomPane.swift`.
