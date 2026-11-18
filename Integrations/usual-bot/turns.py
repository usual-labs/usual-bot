"""What kind of turn a reply ends."""

from __future__ import annotations


def asked_hidden(conversation_history) -> bool:
    """Whether the turn's prompt was hidden: an inline widget's (`window.hermes.send`), or one
    Hermes sent itself. You were looking at the widget when you clicked it, and its answer is the
    widget changing, so the reply isn't news. The prompt is the newest user message, which carries
    the kind it was sent with (`agent/turn_context.py`)."""
    for message in reversed(conversation_history or []):
        if isinstance(message, dict) and message.get("role") == "user":
            return message.get("display_kind") == "hidden"
    return False
