# Architecture

How Usual Bot is put together, for anyone about to change it. For the details of one package, read
its `AGENTS.md` and `docs/agents/` notes; they're kept up to date with the code.

## The big picture

```
┌──────────────────────── Usual Bot (one SwiftUI app, Mac + iPhone) ────────────────────────┐
│ App/            app entry, sign-in presenters, ⌥Space panel, menu bar, notifications      │
│   │                                                                                       │
│   ▼                                                                                       │
│ UsualUI         SwiftUI screens: sidebar, chat, composer, cards, rooms, profile, calls    │
│   │  reads @Observable state, calls methods                                               │
│   ▼                                                                                       │
│ HermesKit       AppModel ─ ChatThread / RoomThread / routines / skills                    │
│                 AuthSession (PKCE, Keychain) · GatewayConnection · JSONRPCChannel         │
└───────────────────────────────┬───────────────────────────────────────────────────────────┘
                                │ HTTPS: sign-in, REST (routines, media, sessions)
                                │ WebSocket /api/ws: JSON-RPC requests, events, server requests
                                ▼
                      Hermes dashboard (hermes dashboard, :9119)
```

- **HermesKit** owns everything about the gateway and the app's state. It depends only on Apple
  frameworks (Foundation, Observation, CryptoKit, Security), has no UI, and is tested with
  `swift test` on its own.
- **UsualUI** owns the screens. It reads HermesKit's observable state and calls its methods; it
  never talks to the gateway directly.
- **App/** is a thin shell: it creates `AppModel`, hands `RootView` a sign-in presenter, and adds
  the pieces that only make sense in an app target (the ⌥Space hotkey and panel, the menu bar item,
  notifications).

## Talking to Hermes

Usual Bot speaks the same protocol as the official Hermes desktop app, to the **dashboard**
listener (default port 9119). It doesn't use the OpenAI-compatible API server, which has no
profile list, no streaming per-profile chat and no rooms.

**Sign-in** (`Auth/`). The app reads `/api/status`, then runs Hermes's native browser sign-in:
a PKCE challenge, the gateway's `/auth/native/authorize` page in the browser, and a redirect to a
one-shot listener on `127.0.0.1` (`LoopbackReceiver`). It exchanges the code for an access token
and a rotating refresh token, stored in the Keychain (`TokenStore`). `AuthSession` refreshes with
one request in flight at a time and saves the new refresh token before using the new access token.

**Connection** (`Transport/`). `GatewayConnection` mints a single-use WebSocket ticket, opens
`/api/ws`, waits for `gateway.ready`, declares its capabilities and pings every 15 seconds.
`JSONRPCChannel` matches requests to responses and splits the stream into events and
server-to-client requests (approvals). `AppModel` reconnects with backoff (300 ms doubling to
15 s) and re-attaches open chats.

**Two dialects.** `gateway.ready` says whether the gateway speaks the **legacy** session protocol
(`hermes dashboard`) or the newer **canonical** one (`hermes gateway`). Chats are implemented for
legacy; canonical gateways connect but chats aren't supported yet.

**Chats** (`Chat/`). Each contact is a Hermes profile; its chat is the profile's hidden
"Bot Chat" session, found or created exactly like the official app does (and never duplicated:
if the lookup fails, the app stops rather than creating a second one). `ChatThread` resumes that
session, sends with `prompt.submit`, and applies streamed events (`message.*`, `tool.*`,
`reasoning.*`) to a `ThreadState` transcript. Extensions add attachments, commands, edit and undo,
side questions (`prompt.btw`), background tasks (`prompt.background`), usage and compression, and
recovery: after a short drop it replays missed events with `session.events.since`.

**Rooms** (`Rooms/`). Rooms don't push events, so `RoomThread` polls `groups.state` and
`groups.log` every 2 seconds while a room is on screen.

**Routines, skills and media.** Routines and skills come from REST routes (`/api/cron/jobs`,
`/api/skills`), and images in replies through the gateway's file routes (`MediaStore`).

**Voice** (`Voice/`, `UsualUI/Call/`). On-device calls use Apple's speech recognition and voices.
GPT-Live calls ask the gateway to open an OpenAI realtime session (the key stays on the gateway)
and run the WebRTC media in a hidden `WKWebView` (`live-call.html`); when the voice model hands a
request to Hermes, it becomes an ordinary turn in the chat.

## State and persistence

- `AppModel` is the root `@MainActor @Observable` object: the gateway, the connection state,
  contacts, threads, rooms, routines and approvals.
- `OfflineCache` keeps the roster and recent messages per gateway in the Caches directory, with
  file protection, so chats open instantly and read offline.
- The Keychain holds tokens; `UserDefaults` holds the gateway address and small UI choices.

## Demo mode

`AppModel.demo()` (`Stores/Demo.swift`) builds a signed-in-looking model with made-up agents,
chats, a room, routines, skills and models. It never connects. Debug builds use it when launched
with `USUALBOT_DEMO=1`; screenshots and UI checks use it too. When you add a feature, add it to
the demo so others can see it without a gateway.

## Tests

- **HermesKit** tests drive a scripted fake socket and HTTP transport
  (`Tests/HermesKitTests/Fakes.swift`): they answer the app's JSON-RPC requests and push events, so
  whole flows (sign-in, attach, stream, approve, reconnect) run without a gateway. Fixtures in
  `Tests/HermesKitTests/Fixtures` are trimmed, anonymised gateway frames.
- **UsualUI** tests cover view logic that can be tested without rendering: the slash menu,
  attachments, the contact list, dictation, spoken replies and the quick message panel.
- **CI** (`.github/workflows/ci.yml`) lints, runs both test suites and builds the app for macOS and
  the iOS Simulator.

## Where to make a change

| You want to… | Change it in |
| --- | --- |
| Support a new gateway method or event | `HermesKit` (`Chat/`, `Rooms/` …), with a test |
| Change how something looks or behaves on screen | `UsualUI` |
| Change sign-in, tokens or the connection | `HermesKit/Auth`, `HermesKit/Transport` |
| Add a Mac- or iPhone-only system feature | `App/` |
| Change build settings, permissions or entitlements | `Config/` |

The package notes in `Packages/*/docs/agents/` list each package's conventions and known issues;
`07-known-issues.md` is worth reading before you touch the UI.
