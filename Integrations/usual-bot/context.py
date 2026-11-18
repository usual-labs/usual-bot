"""Chat context: what a Bot is told about Usual Bot, in the chats the app opened.

The app's chats are made with ``source: "tui"``, so Hermes tells the agent it's in the terminal UI,
where ``MEDIA:`` lines print as text. This says where it really is and what shows there.

Hermes appends a ``pre_llm_call`` hook's context to that turn's user message and keeps it in the
message's ``api_content``, which later turns replay. So it's added once per chat, and again only
when it's gone from the history, as after compression.
"""

from __future__ import annotations

# Finds the text in the history. Changing it adds the new text once to every chat.
MARKER = "<usual-bot-context>"

TEXT = f"""{MARKER}
This chat is in Usual Bot, a Mac and iPhone app for Hermes agents, not in the terminal UI. Usual Labs \
makes it; it isn't Hermes's official app and isn't affiliated with Nous Research.

What shows in it:
- Markdown: headings, bold and italics, links, lists, quotes, tables and code blocks.
- Files: write MEDIA:/absolute/path/to/file alone on its own line. Images, audio and \
video play in the message; any other file shows as a card the user can open. Images from the web show \
with ![alt](https://…). A path written in the text can't be opened, so when you point the user to a file \
they'd want to read or check, also send it on a MEDIA: line.
- Inline widgets: write an HTML file, then put ::preview{{file="/absolute/path.html"}} alone on its own \
line. The app's theme comes in first, as var(--foreground), var(--muted-foreground), var(--accent), \
var(--border) and var(--card), with the app's font, no margins and a transparent background: use those \
and don't set your own. The frame's height follows the page. In this chat, data-hermes-send="prompt" on \
something the user taps, or window.hermes.send("prompt") from a tap, sends that prompt as a hidden \
message; answer it by changing the widget's file, not with prose.
</usual-bot-context>"""


def _texts(message: dict):
    for value in (message.get("api_content"), message.get("content")):
        if isinstance(value, str):
            yield value
        elif isinstance(value, list):  # A message with images: its text parts.
            for part in value:
                if isinstance(part, dict) and isinstance(part.get("text"), str):
                    yield part["text"]


def told(conversation_history) -> bool:
    """Whether the chat's history, as the model will next see it, already has the context."""
    return any(
        MARKER in text
        for message in conversation_history or []
        if isinstance(message, dict) and message.get("role") == "user"
        for text in _texts(message)
    )
