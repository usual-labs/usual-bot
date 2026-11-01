#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    extension AppModel {
        /// A made-up team of agents, their chats, a room and routines, shown as signed in to an
        /// example gateway. For screenshots, and for trying the app without Hermes: Debug builds
        /// launched with `USUALBOT_DEMO=1` use it. It never connects, so nothing can be sent.
        public static func demo(now: Date = .now) -> AppModel {
            let model = AppModel(
                tokenStore: KeychainTokenStore(), http: URLSession.shared,
                defaults: UserDefaults(suiteName: "UsualBotDemo") ?? .standard,
                cache: OfflineCache(directory: .temporaryDirectory.appending(path: "UsualBotDemo")))
            let demo = Demo(now: now)
            let routines = Dictionary(
                uniqueKeysWithValues: demo.agents.map {
                    ($0.id, RoutineList.sample($0.id == "ops" ? demo.opsRoutines : []))
                })
            model.showDemo(
                gateway: Demo.gateway, contacts: demo.agents + [demo.roomContact], threads: demo.threads,
                rooms: [demo.roomContact.id: demo.room], routines: routines,
                skills: Dictionary(uniqueKeysWithValues: demo.agents.map { ($0.id, SkillList.sample(Demo.skills)) }),
                vaults: Dictionary(
                    uniqueKeysWithValues: demo.agents.map {
                        ($0.id, VaultList.sample(items: demo.vaultItems, sources: Demo.vaultSources))
                    }))
            model.media.demoFiles = [Demo.chartPath: Demo.chart()].compactMapValues { $0 }
            return model
        }
    }

    @MainActor
    private struct Demo {
        static let gateway = try! GatewayAddress(parsing: "https://hermes.example.com")

        let now: Date

        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        var agents: [Contact] {
            [
                agent(
                    "forge", "Forge", preview: "Needs your OK to run the migration", minutesAgo: 2,
                    about: "Writes and ships code across the web app and the API; opens pull requests."),
                agent(
                    "atlas", "Atlas", preview: "Turbopuffer fits best: cheapest at our size, and…", minutesAgo: 14,
                    about: "Researches tools, papers and competitors, and writes short recommendations."),
                agent(
                    "scribe", "Scribe", preview: "Two headline options for the launch post", minutesAgo: 95,
                    about: "Drafts posts, release notes and emails in the house style."),
                agent(
                    "ops", "Ops", preview: "All 3 servers healthy, backups verified", minutesAgo: 6 * 60,
                    about: "Watches servers, backups and costs, and reports each morning."),
                agent(
                    "ledger", "Ledger", preview: "October invoices are drafted for review", minutesAgo: 26 * 60,
                    about: "Keeps the books: invoices, receipts and the monthly close."),
            ]
        }

        private func agent(_ id: String, _ name: String, preview: String, minutesAgo: Double, about: String) -> Contact
        {
            Contact(
                id: id, name: name, preview: preview, lastActive: ago(minutesAgo), chatID: "demo-\(id)",
                details: AgentDetails(
                    profile: id, description: about, model: "claude-sonnet-5-5", provider: "anthropic", skillCount: 12))
        }

        var threads: [Contact.ID: ChatThread] {
            var threads = [
                "atlas": ChatThread.sample("atlas", state: ThreadState(history: atlasChat, running: false)),
                "forge": ChatThread.sample("forge", state: ThreadState(history: forgeChat, running: false)),
            ]
            threads["forge"]?.receive(
                ApprovalPrompt(
                    id: "demo-approval", sessionID: "sample",
                    command: "psql \"$STAGING_DATABASE_URL\" -f migrations/0042_search_index.sql",
                    description: "Runs a database migration on staging", choices: [.once, .session, .always]))
            threads["atlas"]?.sideQuestions = [
                SideQuestion(
                    id: "demo-btw", question: "How many pages does docs search hold today?",
                    answer: .answered(
                        "About **40,000 pages**, re-indexed nightly. Turbopuffer stores them for ~$6 a month."))
            ]
            threads["ops"] = ChatThread.sample("ops", state: ThreadState(history: opsChat, running: false))
            threads["ops"]?.receive(
                SecretPrompt(
                    id: "demo-secret", sessionID: "sample",
                    kind: .secret(
                        name: "STATUSPAGE_API_KEY", message: "The status-report skill needs a Statuspage API key.")))
            threads["ops"]?.state.addBackgroundResult(
                task: "Check last night's backups on all three servers",
                result: "All three backups finished between 02:10 and 02:40 and **restore-tested** clean.")
            threads["ops"]?.usage = ChatUsage(
                context: .init(used: 172_000, max: 200_000, percent: 86, estimated: false), input: 2_340_000,
                output: 96_000, calls: 212, compressions: 2)
            threads["ops"]?.backgroundTasks = [
                BackgroundTask(id: "demo-bg", task: "Compare this month's server costs with last month's"),
                BackgroundTask(id: "demo-bg2", task: "Find unused volumes"),
            ]
            for thread in threads.values {
                thread.commands = Demo.commands
                thread.model = ChatModel(name: "claude-sonnet-5-5", provider: "anthropic", reasoning: .medium)
                if thread.contactID == "forge" {
                    // Switched for this chat only, so its menu offers Make Default.
                    thread.model?.name = "claude-opus-5-5"
                }
                thread.modelProviders = Demo.models
                thread.usage =
                    thread.usage
                    ?? ChatUsage(
                        context: .init(used: 76_000, max: 200_000, percent: 38, estimated: false), input: 412_000,
                        output: 31_500, calls: 46)
            }
            for (id, text) in [
                ("scribe", "Two headline options for the launch post"),
                ("ledger", "October invoices are drafted for review"),
            ] {
                threads[id] = ChatThread.sample(
                    id, state: ThreadState(history: [HistoryMessage(role: "assistant", text: text)], running: false))
            }
            threads["ledger"]?.receive(
                SecretPrompt(
                    id: "demo-sudo", sessionID: "sample", kind: .sudo(command: "sudo systemctl restart invoice-worker"))
            )
            for prompt in Demo.vaultPrompts { threads["ledger"]?.receive(prompt) }
            // Shows the warning a gateway on plain http gets.
            threads["ledger"]?.gateway = { try? GatewayAddress(parsing: "http://192.168.1.20:9119") }
            return threads
        }

        /// Made-up logins, a card and an address; there is no secret behind any of them.
        var vaultItems: [VaultItem] {
            let added = ISO8601DateFormatter().string(from: ago(9 * 24 * 60))
            return [
                VaultItem(
                    id: "demo-login", kind: "login", label: "Example Mail", origin: "https://mail.example.com",
                    createdAt: added, identifier: "demo-user@example.com", identifierType: "email", hasOtp: true),
                VaultItem(
                    id: "demo-team", kind: "login", label: "Example Docs", origin: "https://docs.example.com",
                    createdAt: added, identifier: "demo-user", identifierType: "username", backend: "bitwarden"),
                VaultItem(id: "demo-card", kind: "payment", label: "Demo test card", createdAt: added),
                VaultItem(id: "demo-address", kind: "address", label: "1 Example Street", createdAt: added),
            ]
        }

        static let vaultSources = [
            VaultSource(
                name: "local", displayName: "Hermes vault", enabled: true, needsUnlock: false, unlocked: true,
                installed: true),
            VaultSource(
                name: "bitwarden", displayName: "Bitwarden", enabled: true, needsUnlock: true, unlocked: true,
                installed: true),
            VaultSource(
                name: "onepassword", displayName: "1Password", enabled: true, needsUnlock: true, unlocked: false,
                installed: false),
        ]

        static let vaultPrompts = [
            VaultPrompt(
                id: "demo-unlock", sessionID: "sample", kind: .unlock(backend: "bitwarden", displayName: "Bitwarden")),
            VaultPrompt(
                id: "demo-save", sessionID: "sample",
                kind: .saveLogin(origin: "https://billing.example.com", site: "billing.example.com")),
            VaultPrompt(id: "demo-code", sessionID: "sample", kind: .code(site: "billing.example.com", hint: nil)),
        ]

        static let skills = [
            Skill(
                name: "web-research", description: "Search the web and summarise sources with links",
                category: "research",
                usage: 41, provenance: "bundled"),
            Skill(
                name: "release-notes", description: "Draft release notes from merged pull requests",
                category: "writing", usage: 12, provenance: "agent"),
            Skill(
                name: "postgres-migrations", description: "Write and check safe database migrations",
                category: "engineering", usage: 7, provenance: "hub"),
            Skill(
                name: "linkedin-post", description: "Turn notes into a LinkedIn post in the house style",
                category: "writing", enabled: false, usage: 0, provenance: "agent"),
        ]

        static let commands = [
            SlashCommand(
                name: "/web-research", description: "Search the web and summarise sources with links", kind: .skill),
            SlashCommand(
                name: "/release-notes", description: "Draft release notes from merged pull requests", kind: .skill),
            SlashCommand(
                name: "/postgres-migrations", description: "Write and check safe database migrations", kind: .skill),
            SlashCommand(
                name: "/btw", description: "Ask a side question without interrupting", kind: .command),
            SlashCommand(name: "/reasoning", description: "Show or set how hard the agent thinks", kind: .command),
            SlashCommand(name: "/status", description: "Show session, model and token status", kind: .command),
            SlashCommand(name: "/usage", description: "Show token usage and cost for this session", kind: .command),
            SlashCommand(name: "/retry", description: "Send your last message again", kind: .command),
            SlashCommand(name: "/undo", description: "Remove the last exchange", kind: .command),
            SlashCommand(name: "/compress", description: "Summarise the conversation to free context", kind: .command),
        ]

        static let models = [
            ModelProvider(
                slug: "anthropic", name: "Anthropic",
                models: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]),
            ModelProvider(
                slug: "openrouter", name: "OpenRouter", models: ["x-ai/grok-5", "deepseek/deepseek-v4"],
                withoutReasoning: ["deepseek/deepseek-v4"]),
        ]

        static let chartPath = "/home/hermes/.hermes/profiles/ops/cache/cpu-overnight.png"

        private var opsChat: [HistoryMessage] {
            [
                HistoryMessage(role: "user", text: "How did the servers do overnight?"),
                HistoryMessage(role: "tool", name: "terminal", context: "ssh web-1 uptime && df -h /"),
                HistoryMessage(role: "tool", name: "image_generate", context: "CPU chart, last 12 hours"),
                HistoryMessage(
                    role: "assistant",
                    text: """
                        All 3 servers healthy, backups verified. CPU peaked at 61% during the 03:00 \
                        backup and stayed under 40% the rest of the night.
                        MEDIA:\(Demo.chartPath)
                        """),
            ]
        }

        /// The demo's CPU chart: hourly bars over twelve hours, drawn here so the demo needs no files.
        static func chart() -> Data? {
            let (width, height) = (1200, 640)
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1))
            for line in 1...4 { context.fill(CGRect(x: 80, y: 60 + line * 120, width: 1060, height: 2)) }
            let load: [Double] = [22, 18, 16, 61, 34, 19, 17, 21, 28, 35, 38, 31]
            for (hour, percent) in load.enumerated() {
                let peak = percent > 50
                context.setFillColor(
                    peak
                        ? CGColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 1)
                        : CGColor(red: 0.43, green: 0.48, blue: 1, alpha: 1))
                let barHeight = Int(percent / 70 * 480)
                context.fill(CGRect(x: 110 + hour * 86, y: 60, width: 54, height: barHeight))
            }
            guard let image = context.makeImage() else { return nil }
            let output = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            return CGImageDestinationFinalize(destination) ? output as Data : nil
        }

        private var atlasChat: [HistoryMessage] {
            [
                HistoryMessage(
                    role: "user",
                    text: "Compare the three vector databases we shortlisted for docs search and pick one."),
                HistoryMessage(role: "tool", name: "web_search", context: "pgvector vs Qdrant vs Turbopuffer pricing"),
                HistoryMessage(role: "tool", name: "read_file", context: "docs/search/requirements.md"),
                HistoryMessage(role: "tool", name: "web_search", context: "Turbopuffer namespace limits"),
                HistoryMessage(
                    role: "assistant",
                    text: """
                        **Turbopuffer** fits best: it's the cheapest at our size, and search stays fast with \
                        the 40k pages we index today.

                        - **pgvector** keeps everything in Postgres, but index builds slow the database our \
                        app already leans on.
                        - **Qdrant** is quick and full-featured; running it ourselves adds a server to watch.
                        - **Turbopuffer** charges for storage on object storage, about $6 a month for us, and \
                        needs no server.

                        I'd start with a two-week trial behind the existing search box. Want me to draft the \
                        plan for Forge?
                        """),
                HistoryMessage(
                    role: "user", text: "Yes, and keep the old search as a fallback.",
                    reactions: [Reaction(emoji: "👍", byAgent: true)]),
                HistoryMessage(
                    role: "assistant",
                    text: """
                        Done. The plan is in `docs/search/turbopuffer-trial.md` and I've sent Forge the first \
                        task: index the docs nightly, query Turbopuffer first, and fall back to the current \
                        search if it errors or takes over 300 ms.
                        """,
                    reactions: [Reaction(emoji: "🎉", byAgent: false)]),
            ]
        }

        private var forgeChat: [HistoryMessage] {
            [
                HistoryMessage(
                    role: "user",
                    text: "Add the search index migration and run it on staging.\n\n@file:attachments/search-spec.md"),
                HistoryMessage(role: "tool", name: "write_file", context: "migrations/0042_search_index.sql"),
                HistoryMessage(role: "tool", name: "terminal", context: "npm test -- search"),
                HistoryMessage(
                    role: "assistant",
                    text: """
                        The migration adds a GIN index on `pages.body_tsv` and backfills it in batches of \
                        5,000, so staging stays responsive. Tests pass.

                        Running it on staging needs your OK.
                        """),
            ]
        }

        var roomContact: Contact {
            var contact = Contact(room: roomSummary)
            contact.preview = "Scribe: The post is ready for a final read"
            contact.lastActive = ago(30)
            return contact
        }

        var room: RoomThread {
            var seq = 0
            func event(_ kind: String, from actor: JSONValue, _ text: String, minutesAgo: Double) -> JSONValue {
                seq += 1
                return [
                    "room_id": "launch", "seq": .number(Double(seq)), "event_id": .string("demo-\(seq)"),
                    "kind": .string(kind), "actor": actor, "authority_epoch": 1,
                    "payload": ["text": .string(text), "thread_id": "main"],
                    "created_at": .number(ago(minutesAgo).timeIntervalSince1970),
                ]
            }
            let you: JSONValue = ["kind": "user", "id": "you"]
            func member(_ id: String) -> JSONValue { ["kind": "member", "id": .string(id)] }
            let events = [
                event("message.user", from: you, "Launch is Thursday. What's left?", minutesAgo: 42),
                event(
                    "message.member", from: member("forge"),
                    "Search ships behind a flag tomorrow. Staging is waiting on one migration.", minutesAgo: 40),
                event(
                    "message.member", from: member("atlas"),
                    "I checked the three competitors' pricing pages again; nobody changed theirs this week.",
                    minutesAgo: 38),
                event("message.user", from: you, "@scribe how's the post?", minutesAgo: 33),
                event(
                    "message.member", from: member("scribe"),
                    "The post is ready for a final read. I kept it under 600 words and led with the search demo.",
                    minutesAgo: 30),
            ]
            return RoomThread.sample(roomSummary, events: events)
        }

        private var roomSummary: RoomSummary {
            let members: [JSONValue] = ["forge", "atlas", "scribe"].map {
                ["member_id": .string($0), "profile": .string($0), "handle": .string($0)]
            }
            return RoomSummary([
                "room_id": "launch", "name": "Launch crew", "members": .array(members),
                "updated_at": .number(ago(30).timeIntervalSince1970), "latest_seq": 5,
            ])!
        }

        var opsRoutines: [Routine] {
            [
                Routine(
                    id: "health", name: "Morning health check", schedule: "every day at 8am", isOn: true,
                    nextRun: now.addingTimeInterval(9 * 3600), lastRun: ago(15 * 60)),
                Routine(
                    id: "backups", name: "Verify last night's backups", schedule: "every day at 6am", isOn: true,
                    nextRun: now.addingTimeInterval(7 * 3600), lastRun: ago(17 * 60)),
                Routine(
                    id: "costs", name: "Weekly cost report", schedule: "every monday at 9am", isOn: true,
                    nextRun: now.addingTimeInterval(3 * 86_400)),
                Routine(id: "certs", name: "Renew staging certificates", schedule: "0 3 1 * *", isOn: false),
            ]
        }
    }
#endif
