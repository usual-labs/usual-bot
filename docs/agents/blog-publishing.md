# Usual Bot: editorial context and publication prerequisite

## Implemented today

Usual Bot is a native Mac/iPhone client for an existing Hermes gateway. The source
implements gateway sign-in, agents as contacts, ongoing chats, inline approvals
and clarifications, group rooms and profile/routine views. It is not the Hermes
server or a hosted autonomous agent service. Source inspection establishes these
implementations, not working access on every gateway or a public app release.

The intended reader is someone who already operates Hermes profiles and wants a
native messenger interface. Treat that as positioning to test, not verified demand.
Useful content can explain the workflow or a bounded use case; do not claim
unsupported gateway compatibility, native distribution, pricing, paid adoption or
successful real-device operation. Examples must use fictional agents/data.

## Understand the actual app before writing

1. Read `README.md`, `app-shell.md`, both package KBs and current source. Prefer code and
   current package KBs when they disagree. `docs/screenshots/` holds demo-mode screenshots
   with fictional agents, safe to reuse.
2. The user enters their existing gateway address in the connection UI; `AppModel`
   checks support for native sign-in, uses the platform sign-in presenter and keeps
   saved credentials in Keychain. No gateway is supplied by this repository.
3. Once signed in, the UI shows contacts and agent chats. Approvals/clarifications
   appear in the relevant thread; they do not grant an agent blanket authority.
4. The source includes room creation, room messages and agent profile/routine views.
   Availability depends on the connected gateway and its permissions. Disconnected
   cached state is not proof that a new message or action completed remotely.

Source anchors: `App/UsualBotApp.swift`, `App/SignInPresenters.swift`,
`Packages/HermesKit/Sources/HermesKit/Stores/AppModel.swift`,
`Packages/HermesKit/Sources/HermesKit/Auth/`,
`Packages/HermesKit/Sources/HermesKit/Chat/`,
`Packages/HermesKit/Sources/HermesKit/Rooms/`,
`Packages/UsualUI/Sources/UsualUI/RootView.swift` and its Thread/Room/Profile UI.
Do not make real gateway changes, send messages, grant approvals or alter routines
merely to collect marketing evidence.

## No executable blog release path yet

The 23 October 2026 local source inventory found no public landing site, Markdown
blog collection, website package/build, canonical public origin or website deploy
configuration in this repository. `design/avatars/2026-10-22/index.html` is an
internal asset reference, not the product website. The Git repository has local
history but no configured remote at this inspection. `.github/workflows/ci.yml`
only lints/tests Swift and builds Mac/iOS targets; it does not publish a website.

A blog post cannot yet be published at a verified `domain/blog` through this repo.
Do not borrow Usual Design's site, invent a domain or treat a saved Markdown file,
Git commit, native build, GitHub artifact or message as public publication. Current
permission to test one blog release does not itself provision a website target.
The explicit one-post test already authorizes its agent-authored copy and scoped
publication; it does not need another exact-copy approval. The unresolved issue
is the missing release capability, not a request for another creative decision.
This finite test does not create a recurring publication grant.

The owning agent can still prepare a useful, source-backed draft in its operational
workspace and record the missing capability. Keep it unpublished until the existing
site is located or a website has been commissioned and implemented. Do not add an
unused `content/blog` directory here that suggests a functioning renderer.

## Required handoff before a publication test

The website owner must supply or implement these concrete prerequisites:

- Website source/repository and exact canonical domain, with a minimal themed
  landing page, `/blog` index and Markdown article route.
- Filename/frontmatter/draft contract, build command, post discovery and sitemap;
  one agreed CTA that resolves to an actually available product action.
- Authorized Git upstream and hosting project, authenticated agent capability,
  exact deploy command and a known previous deployment/recovery method.
- Current scoped publication authority, followed by draft review and relevant
  content/build checks from that website's own instructions.

Once they exist, update this KB with the real paths/commands. The agent should
write one article, run the declared checks, publish through that exact provider,
and verify public HTTP 200/body/title/canonical, index/sitemap inclusion and CTA.
Record source revision, deployment receipt, live URL, timestamp, checks and recovery
target in its owning operator workspace. Claim success only after public evidence;
report the specific missing step otherwise. No browser testing is required.

## Application checks are a separate boundary

`swift test --package-path Packages/HermesKit`,
`swift test --package-path Packages/UsualUI`, and the Xcode builds in CI check native
application source. They cannot validate a nonexistent blog or establish App Store,
website or gateway acceptance. A blog task does not require native signing/release,
new paid hosting, a database, credentials copied into source or modified gateway
permissions.
