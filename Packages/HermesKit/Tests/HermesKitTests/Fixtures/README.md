# Gateway fixtures

Socket traffic recorded from a real Hermes gateway, then anonymised: every name, title, preview,
ID, path and model is replaced, and the `skin` payload is dropped. Keys, value types and which
fields are `null` are kept exactly as the gateway sent them.

| File | Gateway | What it covers |
| --- | --- | --- |
| `legacy-connect-roster.jsonl` | Hermes 0.21.5, dashboard socket (legacy protocol) | `gateway.ready`, then one `profiles.list` round trip |
| `legacy-chat-turn.jsonl` | Hermes 0.21.5, dashboard socket (legacy protocol) | `prompt.submit` and every event of one streamed reply without tools |
| `canonical-chat-turn.jsonl` | Hermes 0.22.7, gateway listener (canonical protocol) | Making a Bot Chat (`session.list`, `session.create`, `session.resume`), then one streamed reply |
| `canonical-approval.jsonl` | Hermes 0.22.7, gateway listener (canonical protocol) | A turn that asks to run a command, the `approval.respond` that denied it, and the reply after |
| `canonical-routine-delivery.jsonl` | Hermes 0.22.7, gateway listener (canonical protocol) | A routine's result arriving in an open Bot Chat, and the `session.history` read after it |
| `canonical-queue.jsonl` | Hermes 0.23.1, gateway listener (canonical protocol) | Two messages queued behind a running turn, one taken back with `prompt.cancel`, the other starting by itself when the turn ends |
| `canonical-queue-stop.jsonl` | Hermes 0.23.1, gateway listener (canonical protocol) | A queued message taken back, then `session.interrupt`: the turn stops and nothing starts |
| `canonical-goal.jsonl` | Hermes 0.23.1, gateway listener (canonical protocol) | A goal set with `/goal`, carried on by Hermes, stopped mid-reply (`session.control`, `session.interrupt`), continued, judged done and cleared |

The canonical fixtures come from a throwaway gateway with a stand-in model on loopback, so the
replies are echoes. Their `session.resume` histories are cut to the last few rows.

Each line is `{"dir": "in" | "out", "frame": <JSON-RPC frame>}`.

## Recording new fixtures

1. Run a Debug build with `USUALBOT_RECORD_FRAMES=1` in its environment. Frames are appended to
   `usualbot-frames.jsonl` in the app's temporary directory (for the sandboxed Mac app:
   `~/Library/Containers/<bundle id>/Data/tmp/`).
2. Replace everything personal before committing: the recording contains your real conversations.
