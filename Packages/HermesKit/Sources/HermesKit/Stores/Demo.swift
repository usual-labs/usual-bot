#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    extension AppModel {
        /// A made-up team of agents, their chats, a room and routines, shown as signed in to an
        /// example gateway. For screenshots, and for trying the app without Hermes: Debug builds
        /// launched with `USUALBOT_DEMO=1` use it. It never connects: a chat answers what you send
        /// with a scripted reply.
        public static func demo(now: Date = .now, longConversations: Bool = false) -> AppModel {
            let model = AppModel(
                tokenStore: KeychainTokenStore(), http: URLSession.shared,
                defaults: UserDefaults(suiteName: "UsualBotDemo") ?? .standard,
                cache: OfflineCache(directory: .temporaryDirectory.appending(path: "UsualBotDemo")))
            let demo = Demo(now: now, longConversations: longConversations)
            let routines = Dictionary(
                uniqueKeysWithValues: demo.agents.map {
                    ($0.id, DemoRoutines.list(for: $0.id, now: now, skills: Demo.skills))
                })
            model.showDemo(
                gateway: Demo.gateway, contacts: demo.agents + [demo.roomContact], threads: demo.threads,
                rooms: [demo.roomContact.id: demo.room], routines: routines,
                skills: Dictionary(uniqueKeysWithValues: demo.agents.map { ($0.id, SkillList.sample(Demo.skills)) }),
                vaults: Dictionary(
                    uniqueKeysWithValues: demo.agents.map {
                        ($0.id, VaultList.sample(items: demo.vaultItems, sources: Demo.vaultSources))
                    }),
                apps: Dictionary(
                    uniqueKeysWithValues: demo.agents.map { ($0.id, MCPServerList.demo(gateway: Demo.gateway)) }))
            // One Bot hidden, so Settings › General has one to show again.
            model.hiddenBots = [demo.courier]
            model.addDemoBot(demo.courier)
            model.media.demoFiles = [Demo.chartPath: Demo.chart()].compactMapValues { $0 }
            model.usage = .demo(
                agents: { [weak model] in model?.contacts.filter { $0.kind == .agent } ?? [] }, now: now)
            model.gatewaySearch.fetch = { profile, query in
                // sleep-ok: a gateway takes a moment, so "Searching older messages" shows.
                try await Task.sleep(for: .milliseconds(900))
                return DemoSearch.results(profile: profile, query: query)
            }
            model.media.demoMakers = DemoMedia.makers
            return model
        }
    }

    extension ChatThread {
        /// A turn from a pretend gateway: thinking, two tool calls, then a reply as it streams.
        func playDemoReply() {
            let chunks = [
                "I read the notes and ran the checks. ", "Everything you asked about still holds, ",
                "and nothing else needs your attention.\n\n", "- The tests pass.\n", "- The logs are quiet.",
            ]
            func todos(_ read: String, _ check: String) -> JSONValue {
                let list: JSONValue = [
                    ["id": "read", "content": "Read the notes", "status": .string(read)],
                    ["id": "check", "content": "Run the checks", "status": .string(check)],
                ]
                return ["todos": list, "revision": 1]
            }
            let helper: JSONValue = ["subagent_id": "demo-helper", "goal": "Look through the logs"]
            var script: [(pause: Double, type: String, payload: JSONValue)] = [
                (0.5, "todo.updated", todos("in_progress", "pending")),
                (0.4, "tool.start", ["tool_id": "demo-1", "name": "read_file"]),
                (1.2, "tool.complete", ["tool_id": "demo-1"]),
                (0.1, "todo.updated", todos("completed", "in_progress")),
                (0.1, "subagent.start", helper),
                (0.1, "tool.start", ["tool_id": "demo-2", "name": "terminal"]),
                (
                    0.5, "subagent.tool",
                    ["subagent_id": "demo-helper", "tool_name": "read_file", "tool_preview": "app.log"]
                ),
                (0.6, "tool.progress", ["tool_id": "demo-2", "percent": 60]),
                (0.8, "subagent.complete", ["subagent_id": "demo-helper", "status": "completed"]),
                (0.4, "tool.complete", ["tool_id": "demo-2"]),
                (0.1, "todo.updated", todos("completed", "completed")),
                (0.1, "status.update", ["kind": "compacting"]),
                (1.2, "status.update", ["kind": "compacted"]),
            ]
            script += chunks.map { (0.35, "message.delta", ["text": .string($0)]) }
            script.append((0.3, "message.complete", [:]))
            Task {
                for step in script {
                    try? await Task.sleep(for: .seconds(step.pause))
                    apply(GatewayEvent(type: step.type, sessionID: "sample", seq: nil, payload: step.payload))
                }
            }
        }
    }

    @MainActor
    private struct Demo {
        static let gateway = try! GatewayAddress(parsing: "https://hermes.example.com")

        let now: Date
        let longConversations: Bool

        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        var agents: [Contact] {
            [
                agent(
                    "forge", "Forge", preview: "Needs your OK to run the migration", minutesAgo: 2,
                    about: "Writes and ships code across the web app and the API; opens pull requests.",
                    section: Self.product),
                agent(
                    "atlas", "Atlas", preview: "Turbopuffer fits best: cheapest at our size, and…", minutesAgo: 14,
                    about: "Researches tools, papers and competitors, and writes short recommendations.",
                    section: Self.product, isPinned: true),
                agent(
                    "scribe", "Scribe", preview: "Two headline options for the launch post", minutesAgo: 95,
                    about: "Drafts posts, release notes and emails in the house style."),
                agent(
                    "ops", "Ops", preview: Self.opsTask, minutesAgo: 1,
                    about: "Watches servers, backups and costs, and reports each morning.",
                    section: Self.backOffice),
                agent(
                    "ledger", "Ledger", preview: "October invoices are drafted for review", minutesAgo: 26 * 60,
                    about: "Keeps the books: invoices, receipts and the monthly close.",
                    section: Self.backOffice),
            ]
        }

        var courier: Contact {
            agent(
                "courier", "Courier", preview: "The weekly newsletter went out", minutesAgo: 3 * 1440,
                about: "Sends the weekly newsletter and answers replies to it.")
        }

        private static let product = ContactSection(id: "demo-product", name: "Product")
        private static let backOffice = ContactSection(id: "demo-back-office", name: "Back office")

        private func agent(
            _ id: String, _ name: String, preview: String, minutesAgo: Double, about: String,
            section: ContactSection? = nil, isPinned: Bool = false
        ) -> Contact {
            Contact(
                id: id, name: name, preview: preview, lastActive: ago(minutesAgo), isPinned: isPinned,
                chatID: "demo-\(id)",
                details: AgentDetails(
                    profile: id, description: about, model: "claude-sonnet-5-5", provider: "anthropic", skillCount: 12),
                sectionID: section?.id, sectionName: section?.name)
        }

        var threads: [Contact.ID: ChatThread] {
            var threads = [
                // Atlas's question was yesterday and its answer today, so both date labels show.
                "atlas": ChatThread.sample(
                    "atlas",
                    state: ThreadState(
                        history: dated(olderHistory, from: ago(4 * 1440), to: ago(2 * 1440))
                            + dated(Array(atlasChat.prefix(5)), from: ago(1440 + 20), to: ago(1440 + 14))
                            + dated(Array(atlasChat.dropFirst(5)), from: ago(16), to: ago(14)),
                        running: false)),
                "forge": ChatThread.sample(
                    "forge",
                    state: ThreadState(
                        history: dated(olderHistory, from: ago(4 * 1440), to: ago(2 * 1440))
                            + dated(forgeChat, from: ago(6), to: ago(2)),
                        running: false)),
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
            // The list shows a mix, not only Bots that need you: Atlas's last reply is unread
            // and Ops is in the middle of one.
            threads["atlas"]?.unreadCount = 1
            threads["ops"] = ChatThread.sample(
                "ops",
                state: ThreadState(
                    history: dated(opsChat, from: ago(6 * 60 + 4), to: ago(6 * 60))
                        + dated(DemoMedia.voiceMemoTurn, from: ago(5), to: ago(4)), running: false))
            threads["ops"]?.state.addBackgroundResult(
                task: "Check last night's backups on all three servers",
                result: "All three backups finished between 02:10 and 02:40 and **restore-tested** clean.")
            threads["ops"]?.state.sendLocally(Self.opsTask)
            threads["ops"]?.apply(
                GatewayEvent(
                    type: "tool.start", sessionID: "sample", seq: nil,
                    payload: ["tool_id": "demo-du", "name": "terminal", "context": "ssh db-1 du -sh /var/* | sort -h"]))
            // Two messages wait for Ops to finish, so the queue above the message box shows.
            threads["ops"]?.queue = [
                QueuedMessage(id: "demo-queued-1", text: "Then check the same on db-2.", admissionID: "demo"),
                QueuedMessage(
                    id: "demo-queued-2", text: "When both are done, write up what to delete and what to keep.",
                    admissionID: "demo"),
            ]
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
            for (id, text, minutesAgo) in [
                ("scribe", "Two headline options for the launch post", 95.0),
                ("ledger", "October invoices are drafted for review", 26.0 * 60),
            ] {
                let message = HistoryMessage(role: "assistant", text: text)
                threads[id] = ChatThread.sample(
                    id,
                    state: ThreadState(
                        history: dated([message], from: ago(minutesAgo), to: ago(minutesAgo)), running: false))
            }
            DemoSearch.holdBack(threads["ledger"], now: now)
            threads["scribe"]?.receive(
                ClarifyPrompt(
                    id: "demo-question", sessionID: "sample",
                    questions: [
                        .init(
                            id: "headline", text: "Which headline should lead the launch post?",
                            choices: ["Search that keeps up", "Find anything in your docs", "Something else"],
                            allowsMultiple: false)
                    ]))
            threads["scribe"]?.showDemo(DemoConnections.request)
            // Ledger holds the rest of what can need you, so only three Bots do.
            threads["ledger"]?.receive(
                SecretPrompt(
                    id: "demo-sudo", sessionID: "sample", kind: .sudo(command: "sudo systemctl restart invoice-worker"))
            )
            threads["ledger"]?.receive(
                SecretPrompt(
                    id: "demo-secret", sessionID: "sample",
                    kind: .secret(name: "STRIPE_API_KEY", message: "The invoicing skill needs a Stripe API key.")))
            for prompt in Demo.vaultPrompts { threads["ledger"]?.receive(prompt) }
            // Shows the warning a gateway on plain http gets.
            threads["ledger"]?.gateway = { try? GatewayAddress(parsing: "http://192.168.1.20:9119") }
            for thread in threads.values { thread.playsDemoReplies = true }
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
        /// What Ops is working on when the demo opens.
        static let opsTask = "Find what's filling the disk on db-1."

        private var opsChat: [HistoryMessage] {
            [
                HistoryMessage(role: "user", text: "How did the servers do overnight?"),
                HistoryMessage(role: "tool", name: "terminal", context: "ssh web-1 uptime && df -h /"),
                HistoryMessage(role: "tool", name: "image_generate", context: "CPU chart, last 12 hours"),
                HistoryMessage(
                    role: "user",
                    text: """
                        [IMPORTANT: Background process proc_demo completed normally (exit code 0).
                        Command: ./verify-backups.sh --all
                        Output:
                        web-1: backup verified
                        web-2: backup verified
                        db-1: backup verified
                        ]
                        """,
                    displayKind: "process_complete",
                    displayText: "Background Process Finished: ./verify-backups.sh --all"),
                HistoryMessage(
                    role: "assistant",
                    text: """
                        All 3 servers healthy, backups verified.
                        web-1: CPU peaked at 61% during the 03:00 backup.
                        web-2: under 40% all night.
                        db-1: disk at 78%, up from 74% yesterday.
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

        /// Spreads a scripted chat's messages evenly between two times, as the gateway dates them.
        private func dated(_ messages: [HistoryMessage], from start: Date, to end: Date) -> [HistoryMessage] {
            let step = messages.count > 1 ? end.timeIntervalSince(start) / Double(messages.count - 1) : 0
            return messages.enumerated().map { index, message in
                HistoryMessage(
                    role: message.role, text: message.text, name: message.name, context: message.context,
                    toolCallId: message.toolCallId,
                    timestamp: start.addingTimeInterval(step * Double(index)).timeIntervalSince1970,
                    rowId: message.rowId, reactions: message.reactions, displayKind: message.displayKind,
                    displayText: message.displayText, args: message.args)
            }
        }

        /// Uneven rows exercise scrolling without copying anyone’s actual conversations.
        private var olderHistory: [HistoryMessage] {
            guard longConversations else { return [] }
            return (1...80).flatMap { index in
                let paragraph =
                    "Archive item \(index). This is a made-up review of a change to the search service. "
                    + "The checks cover indexing, fallbacks and a staged rollout."
                let reply = Array(repeating: paragraph, count: index % 9 + 1).joined(separator: "\n\n")
                return [
                    HistoryMessage(role: "user", text: "Review archive item \(index)."),
                    HistoryMessage(role: "assistant", text: "## Review \(index)\n\n" + reply),
                ]
            }
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

                        | | Runs on | Cost for us | Watch out for |
                        | --- | --- | ---: | --- |
                        | **pgvector** | our Postgres | nothing extra | index builds slow the database our app leans on |
                        | **Qdrant** | a server we run | ~$40 a month | one more server to watch |
                        | **Turbopuffer** | object storage | ~$6 a month | newer, with a smaller community |

                        I'd start with a two-week trial behind the existing search box. Want me to draft the \
                        plan for Forge?
                        """),
                HistoryMessage(
                    role: "user",
                    text:
                        "Yes, and keep the old search as a fallback. Our limits are on https://docs.example.com/search",
                    reactions: [Reaction(emoji: "👍", byAgent: true)]),
                HistoryMessage(
                    role: "assistant",
                    text: """
                        Done. The plan is in `docs/search/turbopuffer-trial.md` and I've sent Forge the first task.

                        ## Trial plan
                        - Index the docs nightly into Turbopuffer.
                        - Query Turbopuffer first, and fall back to the current search if it errors or takes \
                        over 300 ms.
                        - Compare both for two weeks on [the search dashboard](https://docs.example.com/search/stats).

                        > Keep the old search as a fallback.

                        That stays as you asked, so nobody notices if the trial misbehaves.
                        """,
                    reactions: [Reaction(emoji: "🎉", byAgent: false)]),
                // What a routine set to post in the chat leaves there, as Hermes stores it.
                HistoryMessage(
                    role: "user",
                    text: """
                        [Cronjob "Competitor pricing watch" output — scheduled job, not the user. Review it, act \
                        on anything that needs action, and summarize for the chat.]

                        Northwind cut its Team plan from $12 to $10 a seat. The other two pages haven't changed.
                        """,
                    displayKind: "internal_notification"),
                HistoryMessage(
                    role: "assistant",
                    text:
                        "Northwind is now $2 a seat under us on Team. Nothing to do yet; I'll tell you if Pro moves too."
                ),
            ]
        }

        private var forgeChat: [HistoryMessage] {
            [
                // Another Bot's message, as Hermes stores it.
                HistoryMessage(
                    role: "user",
                    text: """
                        Message from 🤖 Atlas (@atlas): Index the docs nightly into Turbopuffer and query it \
                        first, with the current search as the fallback.
                        """,
                    displayKind: "internal_notification"),
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
            contact.preview = "Scribe: Here's the teaser for the post"
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
            var events = olderHistory.map { message in
                event(
                    message.role == "user" ? "message.user" : "message.member",
                    from: message.role == "user" ? you : member("atlas"), message.text ?? "", minutesAgo: 60)
            }
            events.append(event("message.user", from: you, "Launch is Thursday. What's left?", minutesAgo: 42))
            // Forge leads: it read the question first and gave it to itself and Atlas.
            seq += 1
            events.append([
                "room_id": "launch", "seq": .number(Double(seq)), "event_id": "demo-assignment",
                "kind": "room.assignment", "actor": ["kind": "gateway", "id": "demo"],
                "payload": [
                    "discussion_event_id": "demo-question", "thread_id": "main", "task_id": "demo-routing",
                    "lead_member_id": "forge", "member_ids": ["forge", "atlas"], "fallback": false,
                ],
                "created_at": .number(ago(41).timeIntervalSince1970),
            ])
            events += [
                event(
                    "message.member", from: member("forge"),
                    "Search on Turbopuffer ships behind a flag tomorrow. Staging is waiting on one migration.",
                    minutesAgo: 40),
                event(
                    "message.member", from: member("atlas"),
                    """
                    I checked the three competitors' pricing pages again; nobody changed theirs this week.
                    Tallyhouse: $12 a seat
                    Brightdesk: $15 a seat
                    Pinwheel: free up to 3 seats
                    """,
                    minutesAgo: 38),
                event("message.user", from: you, "@scribe how's the post?", minutesAgo: 33),
                event(
                    "message.member", from: member("scribe"),
                    "The post is ready for a final read. I kept it under 600 words and led with the search demo.",
                    minutesAgo: 31),
                event("message.member", from: member("scribe"), DemoMedia.clipReply, minutesAgo: 30),
            ]
            return RoomThread.sample(
                roomSummary, events: events,
                settings: RoomSettings(
                    purpose: "Ship the Thursday launch", notes: "Staging first. Pricing stays as it is.",
                    routing: .lead, leadID: "forge"))
        }

        private var roomSummary: RoomSummary {
            let members: [JSONValue] = ["forge", "atlas", "scribe"].map {
                ["member_id": .string($0), "profile": .string($0), "handle": .string($0)]
            }
            return RoomSummary([
                "room_id": "launch", "name": "Launch crew", "members": .array(members),
                "updated_at": .number(ago(30).timeIntervalSince1970), "latest_seq": 6,
            ])!
        }
    }
#endif
