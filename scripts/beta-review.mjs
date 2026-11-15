#!/usr/bin/env node
// Hands a TestFlight build to the external test group and sends it to Apple's beta review, through
// the App Store Connect API. The Beta Review workflow runs it; it also runs on a Mac with Node.
//
// Usage: node scripts/beta-review.mjs [--submit] [--build 202611142230] [--platforms mac|iphone]
//                                     [--group "Name"] [--what-to-test "Text"]
//   --submit        without it, only looks everything up and says what it would do
//   --build         a build number, waited for while Apple processes it (up to an hour); the
//                   newest processed build of each platform by default
//   --platforms     only that one; both by default
//   --group         the external group's name; needed only when there's more than one
//   --what-to-test  the build's What to Test; without it, the build keeps the text it has
//
// The key comes from APP_STORE_CONNECT_KEY_ID with APP_STORE_CONNECT_KEY (the .p8's contents) or
// APP_STORE_CONNECT_KEY_PATH. Set APP_STORE_CONNECT_ISSUER_ID only for a team key.
import { createPrivateKey, sign } from "node:crypto";
import { readFileSync } from "node:fs";
import { parseArgs } from "node:util";

const BUNDLE_ID = "labs.usual.UsualBot";
const API = "https://api.appstoreconnect.apple.com";
const PLATFORMS = { mac: "MAC_OS", iphone: "IOS" };
// Builds in these states already went through review, or are in it.
const REVIEWED = ["WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "BETA_APPROVED", "IN_BETA_TESTING"];

const { values: options } = parseArgs({
  options: {
    submit: { type: "boolean", default: false },
    build: { type: "string", default: "" },
    platforms: { type: "string", default: "" },
    group: { type: "string", default: "" },
    "what-to-test": { type: "string", default: "" },
  },
});

function fail(message) {
  console.error(message);
  process.exit(1);
}

function token() {
  const id = process.env.APP_STORE_CONNECT_KEY_ID || fail("Set APP_STORE_CONNECT_KEY_ID.");
  const pem =
    process.env.APP_STORE_CONNECT_KEY ||
    (process.env.APP_STORE_CONNECT_KEY_PATH && readFileSync(process.env.APP_STORE_CONNECT_KEY_PATH, "utf8")) ||
    fail("Set APP_STORE_CONNECT_KEY to the .p8's contents, or APP_STORE_CONNECT_KEY_PATH to the file.");
  const now = Math.floor(Date.now() / 1000);
  const issuer = process.env.APP_STORE_CONNECT_ISSUER_ID;
  // A team key's token names its issuer; an individual key's says it's a user's.
  const who = issuer ? { iss: issuer } : { sub: "user" };
  const part = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const body = `${part({ alg: "ES256", kid: id, typ: "JWT" })}.${part({ ...who, iat: now, exp: now + 15 * 60, aud: "appstoreconnect-v1" })}`;
  // JOSE wants the raw r || s, not the DER Node gives by default.
  const signature = sign("sha256", Buffer.from(body), { key: createPrivateKey(pem), dsaEncoding: "ieee-p1363" });
  return `${body}.${signature.toString("base64url")}`;
}

token(); // fails early when the key is missing

async function api(method, path, body) {
  const response = await fetch(API + path, {
    method,
    // A fresh token each time: one lasts 15 minutes, and waiting for a build can take longer.
    headers: { authorization: `Bearer ${token()}`, ...(body && { "content-type": "application/json" }) },
    body: body && JSON.stringify(body),
  });
  const text = await response.text();
  const json = text ? JSON.parse(text) : {};
  if (!response.ok) {
    const details = (json.errors || []).map((error) => error.detail || error.title).join(" ");
    const hint = response.status === 403 ? " The key isn't allowed to do this." : "";
    fail(`App Store Connect answered ${response.status} to ${method} ${path.split("?")[0]}.${hint} ${details}`);
  }
  return json;
}

const query = (params) => new URLSearchParams(params).toString();

const apps = await api("GET", `/v1/apps?${query({ "filter[bundleId]": BUNDLE_ID })}`);
const app = apps.data.find((entry) => entry.attributes.bundleId === BUNDLE_ID) || fail(`No app has ${BUNDLE_ID}.`);

const groups = await api("GET", `/v1/betaGroups?${query({ "filter[app]": app.id, limit: "200" })}`);
// Internal groups aren't touched here: one with every build gets each upload by itself.
for (const entry of groups.data.filter((entry) => entry.attributes.isInternalGroup)) {
  const builds = entry.attributes.hasAccessToAllBuilds ? "gets every build" : "gets only builds added to it";
  console.log(`Internal group: ${entry.attributes.name}, ${builds}`);
}
const external = groups.data.filter((entry) => !entry.attributes.isInternalGroup);
const candidates = external.filter((entry) => !options.group || entry.attributes.name === options.group);
if (candidates.length !== 1) {
  const names = external.map((entry) => `"${entry.attributes.name}"`).join(", ") || "none";
  fail(`Name one external group with --group. The app has: ${names}.`);
}
const group = candidates[0];
console.log(`External group: ${group.attributes.name}`);

const chosen = options.platforms ? options.platforms.split(/[ ,]+/) : Object.keys(PLATFORMS);
for (const platform of chosen) {
  PLATFORMS[platform] || fail(`Pick mac or iphone, not ${platform}.`);
  await review(platform, PLATFORMS[platform]);
}

async function review(platform, apiPlatform) {
  const params = {
    "filter[app]": app.id,
    "filter[preReleaseVersion.platform]": apiPlatform,
    "filter[expired]": "false",
    sort: "-uploadedDate",
    limit: "1",
    include: "preReleaseVersion,buildBetaDetail",
  };
  if (options.build) params["filter[version]"] = options.build;
  else params["filter[processingState]"] = "VALID";
  let builds = await api("GET", `/v1/builds?${query(params)}`);
  // A build just uploaded shows up a few minutes later, then processes for a few more.
  for (let minute = 0; options.build && minute < 60; minute++) {
    const processing = builds.data[0]?.attributes.processingState;
    if (["VALID", "FAILED", "INVALID"].includes(processing)) break;
    if (minute === 0) console.log(`${platform} ${options.build}: waiting for Apple to process it`);
    await new Promise((resolve) => setTimeout(resolve, 60_000));
    builds = await api("GET", `/v1/builds?${query(params)}`);
  }
  const build = builds.data[0] || fail(`${platform}: no build ${options.build || "is processed yet"}.`);
  const included = (type) => (builds.included || []).find((entry) => entry.type === type)?.attributes || {};
  const name = `${platform} ${included("preReleaseVersions").version} (${build.attributes.version})`;
  const state = included("buildBetaDetails").externalBuildState;
  console.log(`${name}: ${state}`);
  if (build.attributes.processingState !== "VALID") fail(`${name} is ${build.attributes.processingState}, not processed yet.`);

  const localizations = await api("GET", `/v1/builds/${build.id}/betaBuildLocalizations`);
  const localization = localizations.data[0];
  const whatToTest = options["what-to-test"];
  if (!whatToTest && !localization?.attributes.whatsNew) fail(`${name} has no What to Test. Give it with --what-to-test.`);

  const submissions = await api("GET", `/v1/betaAppReviewSubmissions?${query({ "filter[build]": build.id })}`);
  const submitted = submissions.data[0]?.attributes.betaReviewState;
  if (submitted) console.log(`${name}: already submitted, ${submitted}`);

  if (!options.submit) {
    console.log(`${name}: would ${whatToTest ? "set What to Test, " : ""}add it to the group${submitted || REVIEWED.includes(state) ? "" : " and submit it for review"}. Run with --submit to do it.`);
    return;
  }

  if (whatToTest && localization) {
    await api("PATCH", `/v1/betaBuildLocalizations/${localization.id}`, {
      data: { type: "betaBuildLocalizations", id: localization.id, attributes: { whatsNew: whatToTest } },
    });
  } else if (whatToTest) {
    await api("POST", "/v1/betaBuildLocalizations", {
      data: {
        type: "betaBuildLocalizations",
        attributes: { locale: "en-US", whatsNew: whatToTest },
        relationships: { build: { data: { type: "builds", id: build.id } } },
      },
    });
  }
  if (whatToTest) console.log(`${name}: What to Test set`);

  await api("POST", `/v1/betaGroups/${group.id}/relationships/builds`, { data: [{ type: "builds", id: build.id }] });
  console.log(`${name}: in ${group.attributes.name}`);

  if (submitted || REVIEWED.includes(state)) return;
  const submission = await api("POST", "/v1/betaAppReviewSubmissions", {
    data: { type: "betaAppReviewSubmissions", relationships: { build: { data: { type: "builds", id: build.id } } } },
  });
  console.log(`${name}: submitted for review, ${submission.data.attributes.betaReviewState}`);
}
