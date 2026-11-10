// Usual Bot's update check: tells TestFlight builds which build of the app is the latest.
//
// An app can't ask TestFlight that itself, so this Worker asks App Store Connect and answers
// `GET /v1/latest` with `{ app, macos: { version, build }, ios: { version, build } }`. `app` is
// the app's Apple ID, which the app needs to open its page in TestFlight. Requests carry nothing
// about who's asking, and the Worker keeps nothing about them.

const API = "https://api.appstoreconnect.apple.com/v1";
const PLATFORMS = { macos: "MAC_OS", ios: "IOS" };
// Apple's answer is shared for an hour; a failure is tried again after five minutes.
const FRESH_SECONDS = 3600;
const RETRY_SECONDS = 300;
// Apple refuses tokens that live longer than 20 minutes.
const JWT_LIFETIME_SECONDS = 15 * 60;

let cachedJWT = null;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== "/v1/latest") return json({ error: "Not found." }, 404, 0);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return json({ error: "Use GET." }, 405, 0);
    }
    // One cache entry for everyone, whatever the request carried.
    const key = new Request(`${url.origin}/v1/latest`);
    const cached = await caches.default.match(key);
    if (cached) return cached;
    const response = await answer(env);
    ctx.waitUntil(caches.default.put(key, response.clone()));
    return response;
  },
};

async function answer(env) {
  try {
    return json(await latest(env), 200, FRESH_SECONDS);
  } catch (error) {
    console.error("update check failed", error?.name, error?.message);
    return json({ error: "Couldn't reach App Store Connect." }, 502, RETRY_SECONDS);
  }
}

/** The newest build of each platform that testers can install. */
export async function latest(env, get = (path) => ask(path, env)) {
  const apps = await get(`/apps?filter[bundleId]=${encodeURIComponent(env.BUNDLE_ID)}&fields[apps]=bundleId`);
  // The filter also matches bundle IDs that start with this one, such as the notification extension's.
  const app = apps.data?.find((entry) => entry.attributes?.bundleId === env.BUNDLE_ID);
  if (!app) throw new Error(`App Store Connect has no app ${env.BUNDLE_ID}.`);
  const result = { app: app.id };
  for (const [name, platform] of Object.entries(PLATFORMS)) {
    result[name] = await newestBuild(get, app.id, platform, env.BETA_GROUP);
  }
  return result;
}

/**
 * Processed, unexpired builds, newest upload first. With `group` (a beta group's ID), only builds
 * given to that group, such as the external testers' after beta review; without it, the newest
 * processed build, which internal testers can install.
 */
async function newestBuild(get, app, platform, group) {
  const query = new URLSearchParams({
    "filter[app]": app,
    "filter[preReleaseVersion.platform]": platform,
    "filter[processingState]": "VALID",
    "filter[expired]": "false",
    sort: "-uploadedDate",
    limit: "1",
    include: "preReleaseVersion",
    "fields[builds]": "version,preReleaseVersion",
    "fields[preReleaseVersions]": "version",
  });
  if (group) query.set("filter[betaGroups]", group);
  const builds = await get(`/builds?${query}`);
  const build = builds.data?.[0];
  if (!build) return null;
  const versionID = build.relationships?.preReleaseVersion?.data?.id;
  const version = builds.included?.find((entry) => entry.type === "preReleaseVersions" && entry.id === versionID);
  return { version: version?.attributes?.version ?? null, build: build.attributes.version };
}

async function ask(path, env) {
  const response = await fetch(`${API}${path}`, { headers: { Authorization: `Bearer ${await token(env)}` } });
  if (!response.ok) throw new Error(`App Store Connect answered ${response.status} for ${path.split("?")[0]}.`);
  return response.json();
}

/** A team key's token names its issuer (`ASC_ISSUER_ID`); an individual key's says it's a user's. */
async function token(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && cachedJWT.expires - now > 60) return cachedJWT.token;
  const pem = env.ASC_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const expires = now + JWT_LIFETIME_SECONDS;
  const header = base64url(JSON.stringify({ alg: "ES256", kid: env.ASC_KEY_ID, typ: "JWT" }));
  const who = env.ASC_ISSUER_ID ? { iss: env.ASC_ISSUER_ID } : { sub: "user" };
  const claims = base64url(JSON.stringify({ ...who, iat: now, exp: expires, aud: "appstoreconnect-v1" }));
  // WebCrypto's ECDSA signature is already JOSE's raw r || s.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  cachedJWT = { token: `${header}.${claims}.${base64url(signature)}`, expires };
  return cachedJWT.token;
}

function json(value, status, maxAge) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": maxAge > 0 ? `public, max-age=${maxAge}` : "no-store",
    },
  });
}

function base64url(value) {
  const bytes =
    typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value.buffer ?? value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
