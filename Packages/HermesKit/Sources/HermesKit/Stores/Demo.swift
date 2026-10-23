#if DEBUG
    import Foundation

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
                rooms: [demo.roomContact.id: demo.room], routines: routines)
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
            for (id, text) in [
                ("scribe", "Two headline options for the launch post"),
                ("ops", "All 3 servers healthy, backups verified"),
                ("ledger", "October invoices are drafted for review"),
            ] {
                threads[id] = ChatThread.sample(
                    id, state: ThreadState(history: [HistoryMessage(role: "assistant", text: text)], running: false))
            }
            return threads
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
                HistoryMessage(role: "user", text: "Yes, and keep the old search as a fallback."),
                HistoryMessage(
                    role: "assistant",
                    text: """
                        Done. The plan is in `docs/search/turbopuffer-trial.md` and I've sent Forge the first \
                        task: index the docs nightly, query Turbopuffer first, and fall back to the current \
                        search if it errors or takes over 300 ms.
                        """),
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
