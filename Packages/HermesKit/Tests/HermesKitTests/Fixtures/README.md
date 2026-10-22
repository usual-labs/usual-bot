# Gateway fixtures

Socket traffic recorded from a real Hermes gateway, then anonymised: every name, title, preview,
ID, path and model is replaced, and the `skin` payload is dropped. Keys, value types and which
fields are `null` are kept exactly as the gateway sent them.

| File | Gateway | What it covers |
| --- | --- | --- |
| `legacy-connect-roster.jsonl` | Hermes 0.21.5, dashboard socket (legacy protocol) | `gateway.ready`, then one `profiles.list` round trip |
| `legacy-chat-turn.jsonl` | Hermes 0.21.5, dashboard socket (legacy protocol) | `prompt.submit` and every event of one streamed reply without tools |

Each line is `{"dir": "in" | "out", "frame": <JSON-RPC frame>}`.

## Recording new fixtures

1. Run a Debug build with `USUALBOT_RECORD_FRAMES=1` in its environment. Frames are appended to
   `usualbot-frames.jsonl` in the app's temporary directory (for the sandboxed Mac app:
   `~/Library/Containers/<bundle id>/Data/tmp/`).
2. Replace everything personal before committing: the recording contains your real conversations.
