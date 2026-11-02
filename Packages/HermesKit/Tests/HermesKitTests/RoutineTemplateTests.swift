import Foundation
import Testing

@testable import HermesKit

/// Entries shaped like Hermes's `blueprint_catalog_entry` (cron/blueprint_catalog.py).
private let catalog: JSONValue = [
    "blueprints": [
        [
            "key": "morning-brief", "title": "Morning briefing",
            "description": "A short daily briefing: today's calendar, weather, and anything urgent waiting on you.",
            "category": "daily", "tags": ["daily", "briefing"],
            "fields": [
                [
                    "name": "time", "type": "time", "label": "What time?", "default": "08:00", "options": [],
                    "optional": false, "strict": true, "help": "24h local time, e.g. 08:00",
                ],
                [
                    "name": "deliver", "type": "enum", "label": "Where to deliver?", "default": "origin",
                    "options": ["origin", "local", "telegram"], "optional": false, "strict": false, "help": "",
                ],
            ],
            "source": "builtin", "plugin": .null, "schedule": "{minute} {hour} * * *",
            "scheduleHuman": "daily at 08:00", "command": "/blueprint morning-brief time=08:00 deliver=origin",
            "appUrl": "hermes://blueprint/morning-brief?time=08%3A00&deliver=origin",
        ],
        [
            "key": "acme:standup", "title": "Standup nudge", "description": "Plugin-made.", "category": "team",
            "fields": [
                ["name": "minutes", "type": "enum", "label": "How long?", "default": 15, "options": [10, 15]],
                ["name": "mystery", "type": "colour", "label": "", "default": .null],
            ],
            "schedule": "0 9 * * 1-5",
        ],
        ["title": "No key", "schedule": "* * * * *"],
    ]
]

private func encoded(_ value: JSONValue) -> String {
    String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
}

private func field(
    _ name: String, _ kind: RoutineTemplate.Field.Kind, options: [String] = [], optional: Bool = false,
    strict: Bool = true
) -> RoutineTemplate.Field {
    .init(name: name, kind: kind, label: name, options: options, isOptional: optional, isStrict: strict)
}

private func template(_ schedule: String, _ fields: [RoutineTemplate.Field] = []) -> RoutineTemplate {
    RoutineTemplate(key: "t", title: "T", summary: "", fields: fields, scheduleTemplate: schedule)
}

struct RoutineTemplateParsingTests {
    @Test func readsTheCatalog() throws {
        let templates = try RoutineTemplate.catalog(catalog)
        #expect(templates.map(\.key) == ["morning-brief", "acme:standup"])

        let brief = templates[0]
        #expect(brief.title == "Morning briefing")
        #expect(brief.category == "daily")
        #expect(brief.scheduleTemplate == "{minute} {hour} * * *")
        #expect(brief.fields.map(\.kind) == [.time, .choice])
        #expect(brief.questions.map(\.name) == ["time"])
        #expect(brief.hasDelivery)
        #expect(brief.fields[1].isStrict == false)
        #expect(brief.defaults == ["time": "08:00", "deliver": "origin"])

        // Plugins: numbers become text, an unknown type a text field, a blank label the name.
        let plugin = templates[1]
        #expect(plugin.fields[0].defaultValue == "15")
        #expect(plugin.fields[0].options == ["10", "15"])
        #expect(plugin.fields[1].kind == .text)
        #expect(plugin.fields[1].label == "mystery")
        #expect(!plugin.hasDelivery)
    }

    @Test func somethingElseIsntACatalog() {
        #expect(throws: GatewayError.invalidResponse) { try RoutineTemplate.catalog(["detail": "Not Found"]) }
    }

    @Test func choicesInWords() {
        let days = field("recurrence", .days)
        let locale = Locale(identifier: "en_US_POSIX")
        #expect(days.title(for: "everyday", locale: locale) == "Every day")
        #expect(days.title(for: "weekends", locale: locale) == "Weekends")
        #expect(days.title(for: "friday", locale: locale) == "Friday")
        #expect(days.title(for: "no restrictions", locale: locale) == "No restrictions")
    }
}

struct RoutineTemplateFillingTests {
    @Test func fillsPlaceholders() {
        #expect(
            RoutineTemplate.fill("Remind the user: {what}", with: ["what": "stretch"]) == "Remind the user: stretch")
        #expect(RoutineTemplate.fill("{a}{b} and {a}", with: ["a": "1", "b": "2"]) == "12 and 1")
        #expect(RoutineTemplate.fill("0 9 * * *", with: [:]) == "0 9 * * *")
        #expect(RoutineTemplate.fill("Watch {item}", with: [:]) == nil)
    }

    @Test func schedulesAsHermesResolvesThem() {
        let daily = template("{minute} {hour} * * *", [field("time", .time)])
        #expect(daily.schedule(["time": "07:05"]) == "5 7 * * *")
        #expect(daily.schedule(["time": " 7:30 "]) == "30 7 * * *")
        #expect(daily.schedule(["time": "24:00"]) == nil)
        #expect(daily.schedule([:]) == nil)

        let repeating = template("{minute} {hour} * * {dow}")
        #expect(repeating.schedule(["time": "14:00", "recurrence": "weekends"]) == "0 14 * * 0,6")
        #expect(repeating.schedule(["time": "14:00", "recurrence": "Weekdays"]) == "0 14 * * 1-5")
        #expect(repeating.schedule(["time": "14:00", "recurrence": "fortnightly"]) == nil)
        #expect(repeating.schedule(["time": "18:00", "day": "friday"]) == "0 18 * * 5")
        #expect(repeating.schedule(["time": "18:00", "day": "someday"]) == nil)
        #expect(repeating.schedule(["time": "18:00"]) == "0 18 * * *")

        #expect(template("*/{interval_min} * * * *").schedule(["interval_min": "30"]) == "*/30 * * * *")
        #expect(template("*/{interval_min} * * * *").schedule(["interval_min": "0"]) == nil)
        #expect(template("0 */{interval_h} * * *").schedule(["interval_h": "6"]) == "0 */6 * * *")
        #expect(
            template("0 {start_hour}-{end_hour}/{interval_hours} * * 1-5").schedule([
                "start_hour": "9", "end_hour": "17", "interval_hours": "2",
            ]) == "0 9-17/2 * * 1-5")
        // A free-text schedule field wins outright.
        #expect(repeating.schedule(["schedule": "every 2h"]) == "every 2h")
    }

    @Test func checksAnswersBeforeSending() {
        #expect(field("what", .text).problem(with: "  ") == "Fill this in.")
        #expect(field("what", .text, optional: true).problem(with: "") == nil)
        #expect(field("time", .time).problem(with: "8am") == "Use a time like 08:00.")
        #expect(field("time", .time).problem(with: "08:00") == nil)
        #expect(field("count", .choice, options: ["3", "5"]).problem(with: "4") == "Pick one of the choices.")
        #expect(field("deliver", .choice, options: ["local"], strict: false).problem(with: "slack") == nil)

        let reminder = template(
            "{minute} {hour} * * {dow}",
            [field("what", .text), field("time", .time), field("recurrence", .days, options: ["everyday"])])
        #expect(reminder.isComplete(["what": "Stretch", "time": "14:00", "recurrence": "everyday"]))
        #expect(!reminder.isComplete(["what": "", "time": "14:00", "recurrence": "everyday"]))
    }

    @Test func sendsTrimmedAnswersAndTheResultsChoice() {
        let brief = template(
            "{minute} {hour} * * *",
            [field("time", .time), field("note", .text, optional: true), field("deliver", .choice, strict: false)])
        let values = ["time": " 08:00 ", "note": " ", "typo": "x", "deliver": "origin"]
        #expect(
            brief.filled(values, delivery: .thisChat, profile: "scout") == [
                "time": "08:00", "deliver": "bot-chat:scout",
            ])
        #expect(brief.filled(values, delivery: .pastRunsOnly, profile: "scout")["deliver"] == "local")
        #expect(template("0 9 * * *").filled(["deliver": "x"], delivery: .thisChat, profile: "scout") == [:])
    }
}

@MainActor
struct RoutineTemplateGatewayTests {
    private func list(_ http: ScriptedHTTP) -> RoutineList {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, provider: "basic", userID: "u"),
            store: MemoryTokenStore(), http: http)
        return RoutineList(profile: "job-scout", auth: { auth })
    }

    private let base = "http://100.101.102.103:9119/api"

    @Test func loadsTemplatesOnce() async throws {
        let http = ScriptedHTTP { _ in (200, encoded(catalog)) }
        let routines = list(http)
        #expect(routines.templatePhase == .loading)
        await routines.loadTemplates()
        await routines.loadTemplates()
        #expect(routines.templatePhase == .ready)
        #expect(routines.templates.count == 2)
        #expect(http.requests.count == 1)
        #expect(http.requests[0].url?.absoluteString == "\(base)/cron/blueprints?profile=job-scout")
    }

    @Test func anOlderGatewayHasNoneAndIsntAskedAgain() async {
        let http = ScriptedHTTP { _ in (404, #"{"detail":"Not Found"}"#) }
        let routines = list(http)
        await routines.loadTemplates()
        await routines.loadTemplates()
        #expect(routines.templatePhase == .unavailable)
        #expect(http.requests.count == 1)
    }

    @Test func offlineHasNoneForNowAndAsksAgain() async {
        let http = ScriptedHTTP { _ in throw GatewayError.unreachable("Offline") }
        let routines = list(http)
        await routines.loadTemplates()
        #expect(routines.templatePhase == .unavailable)
        await routines.loadTemplates()
        #expect(http.requests.count == 2)
    }

    @Test func createsFromATemplateAndNamesSkillsItCantLoad() async throws {
        let job: JSONValue = [
            "id": "new1", "name": "Weekly review", "prompt": "Run the weekly-review-planning skill's procedure…",
            "schedule": ["kind": "cron", "expr": "0 18 * * 0", "display": "0 18 * * 0"],
            "schedule_display": "0 18 * * 0", "enabled": true, "state": "scheduled", "deliver": "bot-chat:job-scout",
            "skills": ["weekly-review-planning", "google-workspace", "web-research"],
        ]
        let skills: JSONValue = [
            ["name": "weekly-review-planning", "description": "", "enabled": false],
            ["name": "web-research", "description": "", "enabled": true],
        ]
        let http = ScriptedHTTP { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/instantiate") { return (200, encoded(job)) }
            if path.hasSuffix("/skills") { return (200, encoded(skills)) }
            return (200, encoded([job]))
        }
        let routines = list(http)
        let weekly = template(
            "{minute} {hour} * * {dow}",
            [field("time", .time), field("day", .choice), field("deliver", .choice, strict: false)])
        let made = try await routines.create(
            from: RoutineTemplate(
                key: "weekly-review", title: "Weekly review", summary: "", fields: weekly.fields,
                scheduleTemplate: weekly.scheduleTemplate),
            values: ["time": "18:00", "day": "sunday", "deliver": "origin"], delivery: .thisChat)

        let post = http.requests[0]
        #expect(post.httpMethod == "POST")
        #expect(post.url?.absoluteString == "\(base)/cron/blueprints/instantiate?profile=job-scout")
        let body = post.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        #expect(
            body == [
                "blueprint": "weekly-review",
                "values": ["time": "18:00", "day": "sunday", "deliver": "bot-chat:job-scout"],
            ])
        #expect(made.routine.id == "new1")
        #expect(made.routine.prompt.hasPrefix("Run the weekly-review"))
        #expect(
            made.missingSkills == [
                .init(name: "weekly-review-planning", isOff: true), .init(name: "google-workspace", isOff: false),
            ])
        #expect(routines.routines.map(\.id) == ["new1"])
    }

    @Test func noSkillsMeansNoSkillsLookup() async throws {
        let job: JSONValue = [
            "id": "r1", "name": "Custom reminder", "prompt": "Remind the user: stretch", "skills": [],
        ]
        let http = ScriptedHTTP { request in
            request.httpMethod == "POST" ? (200, encoded(job)) : (200, encoded([job]))
        }
        let made = try await list(http).create(
            from: template("0 9 * * *"), values: [:], delivery: .pastRunsOnly)
        #expect(made.missingSkills.isEmpty)
        #expect(!http.requests.contains { $0.url?.path.hasSuffix("/skills") == true })
    }

    @Test func aRefusedAnswerSaysWhyInHermessWords() async {
        let routines = list(ScriptedHTTP { _ in (422, #"{"detail":"invalid time '25:00' — use HH:MM (24h)"}"#) })
        await #expect {
            try await routines.create(from: template("0 9 * * *"), values: [:], delivery: .thisChat)
        } throws: { RoutineList.describe($0) == "invalid time '25:00' — use HH:MM (24h)" }
    }

    @Test func theDemoCreatesFromItsTemplates() async throws {
        let routines = RoutineList.sample([], skills: [Skill(name: "web-research", description: "")])
        await routines.loadTemplates()
        #expect(routines.templates.count == 3)

        let brief = try #require(routines.templates.first { $0.key == "morning-brief" })
        let made = try await routines.create(from: brief, values: ["time": "07:30"], delivery: .thisChat)
        #expect(made.routine.schedule == "30 7 * * *")
        #expect(made.routine.deliver == "bot-chat:sample")
        #expect(made.missingSkills == [.init(name: "google-workspace", isOff: false)])

        let watch = try #require(routines.templates.first { $0.key == "price-watch" })
        #expect(!watch.isComplete(watch.defaults))  // What to watch starts blank.
        var values = watch.defaults
        values["item"] = "https://shop.example.com/kettle"
        let watching = try await routines.create(from: watch, values: values, delivery: .pastRunsOnly)
        #expect(watching.routine.prompt.contains("https://shop.example.com/kettle"))
        #expect(watching.missingSkills.isEmpty)
        #expect(routines.routines.count == 2)
    }
}
