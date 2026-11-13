// Usual Bot's push relay: maps a device ID to its APNs token and forwards sealed notifications.
//
// It never sees what a notification says. The gateway encrypts each one with a key only that
// device and the gateway hold, and the app's notification extension opens it. Apple and this
// Worker see only a generic title, which is what shows if the extension can't open it.

const APNS_HOSTS = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};
// Shown only if the app can't open the sealed text, so it names nothing.
const FALLBACK = {
  message: { title: "Usual Bot", body: "New message" },
  needs_you: { title: "Usual Bot", body: "A Bot needs you" },
  test: { title: "Usual Bot", body: "Notifications from your gateway are working." },
};
const MAX_PUSHES = 20;
const MAX_SEALED = 3000; // APNs takes 4 KB in all.
// Apple refuses a token refreshed more than every 20 minutes and expires it after 60.
const JWT_LIFETIME_MS = 40 * 60 * 1000;

let cachedJWT = null;

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof Refusal) return json({ error: error.message }, error.status);
      console.error("relay error", error?.name, error?.message);
      return json({ error: "Something went wrong in the relay." }, 500);
    }
  },
};

class Refusal extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function route(request, env) {
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);
  if (parts[0] !== "v1") throw new Refusal(404, "Not found.");

  if (parts[1] === "devices" && parts.length === 2 && request.method === "POST") {
    await limit(env.SIGNUPS, sender(request));
    return register(await body(request), env);
  }
  if (parts[1] === "devices" && parts.length === 3) {
    const id = parts[2];
    await limit(env.DEVICE_CHANGES, id);
    await authorizeDevice(request, id, env);
    if (request.method === "PUT") return update(id, await body(request), env);
    if (request.method === "DELETE") {
      await env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(id).run();
      return json({ ok: true });
    }
  }
  if (parts[1] === "send" && parts.length === 2 && request.method === "POST") {
    return send(await body(request), env, false);
  }
  if (parts[1] === "clear" && parts.length === 2 && request.method === "POST") {
    return send(await body(request), env, true);
  }
  throw new Refusal(404, "Not found.");
}

// MARK: Devices

async function register(input, env) {
  const { token, environment } = deviceFields(input);
  const id = randomID(16);
  const secret = randomID(32);
  const sendKey = randomID(32);
  const now = Date.now();
  await env.DB.prepare(
    "INSERT INTO devices (id, token, environment, secret_hash, send_key_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
  )
    .bind(id, token, environment, await hash(secret), await hash(sendKey), now, now)
    .run();
  return json({ id, secret, sendKey }, 201);
}

async function update(id, input, env) {
  const { token, environment } = deviceFields(input);
  await env.DB.prepare("UPDATE devices SET token = ?, environment = ?, updated_at = ? WHERE id = ?")
    .bind(token, environment, Date.now(), id)
    .run();
  return json({ ok: true });
}

function deviceFields(input) {
  const token = String(input.token ?? "");
  const environment = String(input.environment ?? "");
  if (!/^[0-9a-f]{64,200}$/i.test(token)) throw new Refusal(400, "That isn't an APNs device token.");
  if (!(environment in APNS_HOSTS)) throw new Refusal(400, "The environment is sandbox or production.");
  return { token: token.toLowerCase(), environment };
}

async function authorizeDevice(request, id, env) {
  const secret = (request.headers.get("Authorization") ?? "").replace(/^Bearer /, "");
  const row = await env.DB.prepare("SELECT secret_hash FROM devices WHERE id = ?").bind(id).first();
  if (!row) throw new Refusal(404, "This device isn't registered.");
  if (!secret || row.secret_hash !== (await hash(secret))) throw new Refusal(403, "Wrong device secret.");
}

// MARK: Sending

/**
 * From a gateway: `{ pushes: [{ device, key, kind, sealed, thread?, collapse? }] }`.
 * Each push carries its device's send key, so no gateway account is needed. Answers each push's
 * fate, and `gone` tells the gateway to forget that device.
 *
 * `silent` pushes (`/v1/clear`, `{ pushes: [{ device, key, sealed }] }`) show nothing: they wake the
 * app to take down notifications about a chat read on another device. A separate route, so a
 * gateway's clears sent to an older relay fail rather than show "New message".
 */
async function send(input, env, silent) {
  const pushes = Array.isArray(input.pushes) ? input.pushes : [];
  if (pushes.length === 0 || pushes.length > MAX_PUSHES) {
    throw new Refusal(400, `Send between 1 and ${MAX_PUSHES} pushes.`);
  }
  const results = await Promise.all(pushes.map((push) => sendOne(push, env, silent)));
  return json({ results });
}

async function sendOne(push, env, silent) {
  const device = String(push.device ?? "");
  const kind = silent ? "read" : push.kind in FALLBACK ? push.kind : "message";
  const sealed = String(push.sealed ?? "");
  if (sealed.length > MAX_SEALED) return { device, status: "refused", reason: "TooLarge" };
  if (silent && !sealed) return { device, status: "refused", reason: "NothingSealed" };

  // Before the lookup, so a flood for one device costs no reads either.
  if (!(await env.PUSHES.limit({ key: device })).success) return { device, status: "limited" };

  const row = await env.DB.prepare("SELECT token, environment, send_key_hash FROM devices WHERE id = ?")
    .bind(device)
    .first();
  if (!row) return { device, status: "gone" };
  if (!push.key || row.send_key_hash !== (await hash(String(push.key)))) {
    return { device, status: "refused", reason: "WrongKey" };
  }

  // Apple wants a background push to carry no alert, sound or badge, and to go at priority 5.
  const payload = silent
    ? { aps: { "content-available": 1 }, kind }
    : { aps: { alert: FALLBACK[kind], sound: "default", "mutable-content": 1 }, kind };
  if (sealed) payload.s = sealed;
  if (push.thread && !silent) payload.aps["thread-id"] = String(push.thread).slice(0, 64);

  const headers = {
    authorization: `bearer ${await providerToken(env)}`,
    "apns-topic": env.APNS_TOPIC,
    "apns-push-type": silent ? "background" : "alert",
    "apns-priority": silent ? "5" : "10",
    "apns-expiration": String(Math.floor(Date.now() / 1000) + 24 * 3600),
  };
  if (push.collapse && !silent) headers["apns-collapse-id"] = String(push.collapse).slice(0, 64);

  const response = await fetch(`${APNS_HOSTS[row.environment]}/3/device/${row.token}`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });
  if (response.ok) return { device, status: "sent" };

  const reason = (await response.json().catch(() => ({}))).reason ?? `HTTP${response.status}`;
  if (response.status === 410 || reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic") {
    await env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(device).run();
    return { device, status: "gone", reason };
  }
  if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken") cachedJWT = null;
  console.error("apns refused", response.status, reason);
  return { device, status: "failed", reason };
}

/** Apple's provider token: an ES256 JWT signed with the team's .p8 key. */
async function providerToken(env) {
  if (cachedJWT && Date.now() - cachedJWT.at < JWT_LIFETIME_MS) return cachedJWT.token;
  const pem = env.APNS_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = base64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) }));
  // WebCrypto's ECDSA signature is already JOSE's raw r || s.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const token = `${header}.${claims}.${base64url(signature)}`;
  cachedJWT = { token, at: Date.now() };
  return token;
}

// MARK: Helpers

async function limit(limiter, key) {
  if (!(await limiter.limit({ key })).success) {
    throw new Refusal(429, "Too many requests. Try again in a minute.");
  }
}

/** Who's asking: their IP address, or for IPv6 their /64, which one household or phone usually has. */
function sender(request) {
  const address = request.headers.get("CF-Connecting-IP") ?? "unknown";
  if (!address.includes(":")) return address;
  const [head, tail] = address.split("::");
  const front = head ? head.split(":") : [];
  const back = tail ? tail.split(":") : [];
  const groups = [...front, ...Array(Math.max(0, 8 - front.length - back.length)).fill("0"), ...back];
  return `${groups.slice(0, 4).map((group) => group.replace(/^0+(?=.)/, "")).join(":")}::/64`;
}

async function body(request) {
  try {
    return await request.json();
  } catch {
    throw new Refusal(400, "Send JSON.");
  }
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });
}

function randomID(bytes) {
  return base64url(crypto.getRandomValues(new Uint8Array(bytes)));
}

async function hash(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function base64url(value) {
  const bytes =
    typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value.buffer ?? value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
