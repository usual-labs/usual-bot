"""What kind of turn a reply ends."""

from __future__ import annotations

# Another Bot's message, as Hermes words it (`tools/bot_mode_dm.py`): `Message from 🤖 <name>
# (@<handle>): <body>`, the body starting with `[no reply needed]` when nothing goes back.
_BOT_PREFIX = "Message from 🤖 "
_NO_REPLY = "[no reply needed]"


def bot_sender(text) -> tuple[str, bool] | None:
    """Who wrote a turn's message, when another Bot did, and whether it's a note that wants no
    reply. A name can hold brackets of its own, so the handle is the last ` (@` before `): `."""
    if not isinstance(text, str) or not text.startswith(_BOT_PREFIX):
        return None
    sender, colon, body = text[len(_BOT_PREFIX):].partition("): ")
    name, at, _ = sender.rpartition(" (@")
    if not colon or not at or not name.strip():
        return None
    return name.strip(), body.lstrip().startswith(_NO_REPLY)


# What Usual Bot puts before the `submission_id` of a prompt an inline widget sends
# (`ChatThread.widgetPrefix`); Hermes keeps it in the row's `display_metadata`.
_WIDGET_SUBMISSION = "widget-"


def asked_hidden(conversation_history) -> bool:
    """Whether Hermes sent the turn's prompt itself, hidden, such as a goal's next step. A widget's
    prompt is hidden too but notifies like typing: you can tap and leave before the reply, and an
    open chat already keeps every device quiet. The prompt is the newest user message, which
    carries its kind and metadata (`agent/turn_context.py`)."""
    for message in reversed(conversation_history or []):
        if isinstance(message, dict) and message.get("role") == "user":
            if message.get("display_kind") != "hidden":
                return False
            metadata = message.get("display_metadata")
            submission = metadata.get("submission_id") if isinstance(metadata, dict) else None
            return not (isinstance(submission, str) and submission.startswith(_WIDGET_SUBMISSION))
    return False


def asked_by_bot(conversation_history) -> bool:
    """Whether another Bot started the turn (`Message from 🤖 …`). The reply goes back to that Bot,
    whose own answer to you is the news; the app folds this exchange away. A question or an approval
    in it still notifies: those go through `on_human_input_request`."""
    for message in reversed(conversation_history or []):
        if isinstance(message, dict) and message.get("role") == "user":
            content = message.get("content")
            return message.get("display_kind") == "internal_notification" and bot_sender(content) is not None
    return False


# A Bot's word for "nothing to say" (`LIVE_GATEWAY_SILENT_MARKERS` in `gateway/response_filters.py`).
_SILENT = {"[SILENT]", "SILENT", "NO_REPLY", "NO REPLY", "[静默]", "静默", "[沉默]", "沉默"}


def _is_silent(text: str) -> bool:
    stripped = text.strip()
    if not 0 < len(stripped) <= 64:
        return False
    # Stray punctuation round it (".NO_REPLY", "*NO_REPLY*"), but brackets stay: "[SILENT" isn't one.
    bare = stripped.strip(".,;:!?*_`'\"~-").strip()
    return any(" ".join(form.upper().split()) in _SILENT for form in (stripped, bare))


def said(response) -> str:
    """What a reply says to you: ``""`` when the Bot chose not to reply (``[SILENT]``, ``NO_REPLY``),
    and without a marker that closes a real reply on its own line. Hermes keeps the marker in the
    history; only its own chats drop it before you see it."""
    try:
        from gateway.response_filters import is_intentional_silence_response, strip_trailing_silence_marker

        return "" if is_intentional_silence_response(response) else strip_trailing_silence_marker(response)
    except Exception:  # A Hermes without it: the same rule, by hand.
        pass
    if not isinstance(response, str) or _is_silent(response):
        return ""
    head, _, tail = response.rstrip().rpartition("\n")
    return head.rstrip() if head.strip() and _is_silent(tail) else response
