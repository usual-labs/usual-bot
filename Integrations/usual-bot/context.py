"""Chat context: what a Bot is told about Usual Bot, in the chats the app opened.

The app's chats are made with ``source: "tui"``, so Hermes tells the agent it's in the terminal UI,
where ``MEDIA:`` lines print as text. This says where it really is, how to write there, and what
shows.

Hermes appends a ``pre_llm_call`` hook's context to that turn's user message and keeps it in the
message's ``api_content``, which later turns replay. So it's added once per chat, and again only
when it's gone from the history, as after compression.

How to write comes first and in prose: models copy the shape of their instructions, and a list of
what renders reads as an invitation to use all of it. One note far back in a long chat loses to the
replies written since, so every turn the user starts also gets `VOICE`, one line at the end.
"""

from __future__ import annotations

from .turns import bot_sender  # noqa: F401  (the hook reads it from here)

# Finds the text in the history. Changing it adds the new text once to every chat.
MARKER = '<usual-bot-context version="2">'

TEXT = f"""{MARKER}
This chat is in Usual Bot, a messenger for Hermes agents on Mac and iPhone, not the terminal UI. Usual \
Labs makes it; it isn't Hermes's official app and isn't affiliated with Nous Research. This replaces any \
earlier usual-bot-context in this chat.

Write to the user the way a capable colleague texts: short messages in plain sentences. Most replies are \
one to four sentences. Lead with the answer or what happened, and stop there. End with one question or \
offer only when there's a real next step. Before work that takes more than a few seconds, first send one \
short line saying what you're on, then the result when you have it. Say what happened, not how: leave out \
tool names, job ids, file sizes and paths unless the user needs them to act. When the answer is long, like \
a plan or a few options, write short paragraphs that each open with a few bold words. Keep tables for \
comparing several options side by side, and leave headings and report sections ("What I did", \
"Summary") out of chat. If your own instructions set a different voice, theirs wins.

For example, asked to move a meeting, reply "Moved it to Thursday at 3. Sam was free then, and he has the \
new invite." Asked a question you need to look into, reply "On it, checking their pricing pages." and \
then, in your next message, the answer.

What shows here: Markdown, links and code blocks render. To send a file, write \
MEDIA:/absolute/path/to/file alone on its own line: images, audio and video play in the message, and any \
other file shows as a card the user can open. Images from the web show with ![alt](https://…). A path \
written in the text can't be opened, so when you point the user to a file they'd want to read or check, \
also send it on a MEDIA: line. For an inline widget, write an HTML file, then put \
::preview{{file="/absolute/path.html"}} alone on its own line. The app's theme comes in first, as \
var(--foreground), var(--muted-foreground), var(--accent), var(--border) and var(--card), with the app's \
font, no margins and a transparent background: use those and don't set your own. The frame's height \
follows the page. In this chat, data-hermes-send="prompt" on something the user taps, or \
window.hermes.send("prompt") from a tap, sends that prompt as a hidden message; answer it by changing the \
widget's file, not with prose.
</usual-bot-context>"""

# Every turn the user starts, and every room turn. Its own tag, so it never passes for `TEXT`.
# The line before long work is repeated here and holds whatever the voice: Bots with a SOUL voice of
# their own read a plain "unless your own instructions…" as leave to skip it.
VOICE = ("<usual-bot-voice>Usual Bot is a messenger: reply like a text, with the answer first in a few "
         "short plain sentences. Your own instructions can set another tone and length, but whatever voice "
         "they set: before work that takes more than a few seconds, first send one short line saying what "
         "you're on.</usual-bot-voice>")


def bot_turn(name: str, note: bool) -> str:
    """What a Bot is told on a turn another Bot started. The app folds the exchange away, so a
    reply written to the user would be read by the other Bot and missed by the user. Its own tag, so
    it never passes for `TEXT` in `told`."""
    if note:
        return (f"<usual-bot-turn>\nThis message is from {name}, another Bot, not from the user. Nothing goes back "
                f"to {name}: do what it asks and finish quietly. Ask the user only if you can't go on "
                "without them.\n</usual-bot-turn>")
    return (f"<usual-bot-turn>\nThis message is from {name}, another Bot, not from the user. Your final reply goes "
            f"back to {name} by itself, and the user sees this exchange folded away. Write the reply to {name}: "
            "lead with the result, keep it short, and don't address the user. Ask the user only if you can't "
            "go on without them.\n</usual-bot-turn>")


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
