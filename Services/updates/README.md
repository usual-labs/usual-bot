# Usual update check

A Cloudflare Worker at `bot.usual.dev` that tells TestFlight builds of Usual Bot which build is the
latest, so the app can offer it. An app can't ask TestFlight that, so the Worker asks App Store
Connect.

Only TestFlight builds ask (`USUAL_UPDATES = YES`, which `scripts/testflight.sh` sets). The request
is a plain `GET` with nothing about the device or the person; the Worker stores nothing and logs
only its own failures.

## API

`GET /v1/latest` answers:

```json
{
  "app": "1234567890",
  "macos": { "version": "0.5.0", "build": "202611090217" },
  "ios": { "version": "0.5.0", "build": "202611090217" }
}
```

`app` is the app's Apple ID, which the app needs to open its page in TestFlight
(`itms-beta://beta.itunes.apple.com/v1/app/<app>`). A platform with no build is `null`. Apple's
answer is cached for an hour; when App Store Connect can't be reached it answers 502, cached for five
minutes, and the app keeps what it knew.

## Which builds

With `BETA_GROUP` empty, it's the newest processed, unexpired build: what internal testers can
install. Once external testers join through a public link, set `BETA_GROUP` in `wrangler.toml` to
that group's ID (the last part of the group's URL in App Store Connect), so only builds given to it
are offered, after beta review. Internal testers then hear about those builds only.

## Set it up

1. **A key.** An App Store Connect API key. It only reads apps and builds here, but holds whatever
   its role allows, so give it the least you can: a team key with the **Developer** role, or an
   individual key from a user limited to Usual Bot, as in
   [Releasing](../../docs/guides/releasing.md#the-upload-key).
2. **Secrets and deploy**, from this folder, with Wrangler signed in to the account in
   `wrangler.toml`. A team key also needs `ASC_ISSUER_ID`, the issuer ID at the top of App Store
   Connect's Team Keys page; an individual key leaves it unset.

   ```sh
   npx wrangler@4 secret put ASC_KEY < ApiKey_XXXXXXXXXX.p8
   npx wrangler@4 secret put ASC_KEY_ID
   npx wrangler@4 secret put ASC_ISSUER_ID
   npx wrangler@4 deploy
   ```

3. **Check it:** `curl -s https://bot.usual.dev/v1/latest` shows the latest build numbers, which
   should match TestFlight.

A fork with its own bundle ID sets `BUNDLE_ID`, `account_id` and the route, and its own address in
`USUAL_UPDATES_URL_YES` (`Config/Shared.xcconfig`).
