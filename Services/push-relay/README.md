# Usual push relay

A Cloudflare Worker and D1 database at `push.usual.dev` that hands sealed notifications from
gateways to Apple's push service. It holds Usual Bot's APNs key, which only the app's signer can
have, so each gateway doesn't need one.

It can't read what it carries. The gateway plugin ([`Integrations/hermes-push`](../../Integrations/hermes-push/README.md))
seals each notification with a key the device made and gave only to its gateway, and the app's
notification extension opens it. The relay adds a generic "New message", which is what shows if a
device can't open it.

## What it stores

One row per device in D1: the APNs token, sandbox or production, and SHA-256 hashes of two random
secrets. The device keeps the first, to update or remove its row. Its gateway keeps the second, the
send key, to push to it. No accounts, names, gateways or message text. A row goes when Apple says the
token is dead.

Sign-ups are limited by address, and changes and pushes by device. The limits are loose by design
(Cloudflare counts per location), so they stop a flood, not a burst. Over the limit, a call answers
429, and a push in `/v1/send` answers `limited`.

## API

| Call | Who | Does |
| --- | --- | --- |
| `POST /v1/devices` `{token, environment}` | the app | Registers; answers `{id, secret, sendKey}` |
| `PUT /v1/devices/:id` `{token, environment}` | the app, `Authorization: Bearer <secret>` | New token |
| `DELETE /v1/devices/:id` | the app, `Authorization: Bearer <secret>` | Removes the row |
| `POST /v1/send` `{pushes: [{device, key, kind, sealed, thread?, collapse?}]}` | a gateway | Up to 20 pushes; answers each one's `status`: `sent`, `gone` (forget the device), `refused`, `limited` or `failed` |
| `POST /v1/clear` `{pushes: [{device, key, sealed}]}` | a gateway | The same, as silent background pushes that take down a chat's notifications |

`kind` is `message`, `needs_you` or `test`. `sealed` is base64 AES-GCM (nonce, ciphertext, tag) of
JSON with `title`, `body`, `chat`, `kind` and `sound`. `thread` groups a chat's notifications
without naming it. A clear's `sealed` holds only `kind: "read"` and `chat`. It has a route of its
own so that clears sent to an older relay fail there rather than show "New message".

## Run your own

A fork with its own bundle ID needs its own relay, as an APNs key reaches only its own team's apps.

1. At developer.apple.com, turn on Push Notifications for your App ID, then make a key under
   **Keys** with **Apple Push Notifications service (APNs)**, for Sandbox & Production.
2. In `wrangler.toml`, set `account_id`, the route, `APNS_KEY_ID`, `APNS_TEAM_ID` and `APNS_TOPIC`
   (your bundle ID).
3. Create the database and deploy:

   ```sh
   npx wrangler d1 create usual-push        # put its database_id in wrangler.toml
   npx wrangler d1 execute usual-push --remote --file schema.sql
   npx wrangler secret put APNS_KEY < AuthKey_XXXXXXXXXX.p8
   npx wrangler deploy
   ```

4. Build the app with `USUAL_PUSH = YES` and `USUAL_PUSH_RELAY_URL_YES` set to your relay
   (`Config/Local.xcconfig.example`).

`wrangler dev` can't reach APNs: workerd has no HTTP/2 client. Test against a deployed Worker.
