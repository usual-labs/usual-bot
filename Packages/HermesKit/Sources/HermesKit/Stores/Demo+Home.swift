#if DEBUG
    import Foundation

    extension AppModel {
        /// The demo's second gateway, "Home": a smaller made-up team, one of them the gateway's own
        /// `default` profile, as every gateway has.
        func showHomeDemo(now: Date) {
            let home = DemoHome(now: now)
            showDemo(
                gateway: DemoHome.gateway, contacts: home.agents, threads: home.threads, rooms: [:],
                routines: Dictionary(uniqueKeysWithValues: home.agents.map { ($0.id, RoutineList.sample([])) }),
                skills: Dictionary(uniqueKeysWithValues: home.agents.map { ($0.id, SkillList.sample([])) }),
                vaults: [:], apps: [:])
        }
    }

    @MainActor
    struct DemoHome {
        static let gateway = try! GatewayAddress(parsing: "https://home.example.com")

        let now: Date

        private func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        var agents: [Contact] {
            [
                agent(
                    "default", "Hermes", preview: "The heating's back on the winter schedule", minutesAgo: 3,
                    about: "Runs the house: heating, lights and the shopping list."),
                agent(
                    "pantry", "Pantry", preview: "Three dinners for this week, all under 30 minutes", minutesAgo: 50,
                    about: "Plans meals from what's in the fridge and writes the shopping list."),
                agent(
                    "garden", "Garden", preview: "Frost tonight: cover the lemon tree", minutesAgo: 8 * 60,
                    about: "Keeps the watering schedule and warns about the weather."),
            ]
        }

        private func agent(_ id: String, _ name: String, preview: String, minutesAgo: Double, about: String) -> Contact
        {
            Contact(
                id: id, name: name, preview: preview, lastActive: ago(minutesAgo), chatID: "demo-home-\(id)",
                details: AgentDetails(
                    profile: id, description: about, model: "claude-haiku-5-5", provider: "anthropic", skillCount: 4))
        }

        var threads: [Contact.ID: ChatThread] {
            let hermes = ChatThread.sample(
                "default",
                state: ThreadState(
                    history: [
                        HistoryMessage(
                            role: "user", text: "It's getting cold. Put the heating back on the winter schedule.",
                            timestamp: ago(5).timeIntervalSince1970),
                        HistoryMessage(role: "tool", name: "home_assistant", context: "climate.set_schedule winter"),
                        HistoryMessage(
                            role: "assistant",
                            text: """
                                The heating's back on the **winter schedule**: 21° from 6:30 to 9:00 and from \
                                17:00 to 22:30, and 16° overnight.
                                """, timestamp: ago(3).timeIntervalSince1970),
                    ], running: false))
            hermes.unreadCount = 1
            hermes.playsDemoReplies = true
            let pantry = ChatThread.sample(
                "pantry",
                state: ThreadState(
                    history: [
                        HistoryMessage(
                            role: "user", text: "What can I cook this week with what's in the fridge?",
                            timestamp: ago(52).timeIntervalSince1970),
                        HistoryMessage(
                            role: "assistant",
                            text: """
                                Three dinners, all under 30 minutes:

                                - Leek and potato soup
                                - Chickpea curry with the spinach
                                - Omelettes with the last of the mushrooms

                                You'd only need to buy coriander and a lemon.
                                """, timestamp: ago(50).timeIntervalSince1970),
                    ], running: false))
            pantry.playsDemoReplies = true
            return ["default": hermes, "pantry": pantry]
        }
    }
#endif
