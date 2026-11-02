#if DEBUG
    import Foundation

    /// A template in the demo, with the prompt and skills Hermes would keep to itself.
    struct DemoTemplate {
        let template: RoutineTemplate
        let prompt: String
        let skills: [String]

        /// Three of Hermes's built-in kinds: one with a skill the demo agents lack, one with a skill
        /// they have, and one with none.
        static let all = [
            DemoTemplate(
                template: RoutineTemplate(
                    key: "morning-brief", title: "Morning briefing",
                    summary:
                        "A short daily briefing: today's calendar, the weather, and anything urgent waiting on you.",
                    category: "daily", fields: [time("08:00"), deliver], scheduleTemplate: "{minute} {hour} * * *"),
                prompt:
                    "Produce a concise morning briefing for the user: today's calendar events, the local weather, and any urgent items. Keep it short and scannable.",
                skills: ["google-workspace"]),
            DemoTemplate(
                template: RoutineTemplate(
                    key: "price-watch", title: "Price watch",
                    summary: "Watch a product, flight or listing and hear when the price drops or it's back in stock.",
                    fields: [
                        .init(
                            name: "item", kind: .text, label: "What exactly to watch?",
                            help: "A link or a precise description: variant, dates, seller"),
                        .init(
                            name: "condition", kind: .text, label: "Alert me when…",
                            defaultValue: "the all-in price drops below my target",
                            help: "A price to beat (say the currency), or back in stock"),
                        .init(
                            name: "interval_h", kind: .choice, label: "How often?", defaultValue: "6",
                            options: ["1", "3", "6", "12", "24"], help: "hours between checks"),
                        deliver,
                    ], scheduleTemplate: "0 */{interval_h} * * *"),
                prompt:
                    "Check this watch: {item}. Alert condition: {condition}. Compare against what you found last time and only speak up when the condition is met; otherwise respond with [SILENT].",
                skills: ["web-research"]),
            DemoTemplate(
                template: RoutineTemplate(
                    key: "custom-reminder", title: "Custom reminder",
                    summary: "A recurring reminder in your own words, on your schedule.",
                    fields: [
                        .init(
                            name: "what", kind: .text, label: "Remind me to…", defaultValue: "take a break and stretch"),
                        time("14:00"),
                        .init(
                            name: "recurrence", kind: .days, label: "Repeat on", defaultValue: "everyday",
                            options: ["everyday", "weekdays", "weekends"]),
                        deliver,
                    ], scheduleTemplate: "{minute} {hour} * * {dow}"),
                prompt: "Remind the user: {what}", skills: []),
        ]

        private static func time(_ value: String) -> RoutineTemplate.Field {
            .init(
                name: "time", kind: .time, label: "What time?", defaultValue: value, help: "24h local time, e.g. 08:00")
        }

        private static let deliver = RoutineTemplate.Field(
            name: "deliver", kind: .choice, label: "Where to deliver?", defaultValue: "origin",
            options: ["origin", "local", "telegram"], isStrict: false)
    }
#endif
