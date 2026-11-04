import Foundation
import Synchronization
import Testing

@testable import HermesKit

struct GatewaySnippetTests {
    private func marked(_ raw: String) -> (text: String, marked: [String]) {
        let parsed = GatewaySearchResult.parse(raw)
        return (parsed.text, parsed.matches.map { String(parsed.text[$0]) })
    }

    @Test func readsFTSMarksAndCuts() {
        let parsed = marked("...two >>>Hetzner<<< invoices are missing, so I've asked >>>their<<< billing...")
        #expect(parsed.text == "…two Hetzner invoices are missing, so I've asked their billing…")
        #expect(parsed.marked == ["Hetzner", "their"])
    }

    @Test func takesOutMarkdownAndLineBreaks() {
        let parsed = marked("All but two.\n\n- the **>>>Hetzner<<<** invoices\n  are `missing`")
        #expect(parsed.text == "All but two. - the Hetzner invoices are missing")
        #expect(parsed.marked == ["Hetzner"])
    }

    @Test func marksSpanningWordsAndAMarkAtTheStart() {
        let parsed = marked(">>>VAT return<<< filed")
        #expect(parsed.text == "VAT return filed")
        #expect(parsed.marked == ["VAT return"])
    }

    @Test func aSnippetWithoutMarksHighlightsTheQuery() throws {
        // Hermes's LIKE fallback cuts the raw text and marks nothing.
        let result = GatewaySearchResult(
            sessionId: "s", lineageRoot: nil, role: "user", snippet: "sk the Hetzner billing team")
        let search = try #require(MessageSearch("hetzner"))
        let hit = try #require(result.hit(in: "ledger", query: search))
        #expect(hit.matches.map { String(hit.snippet[$0]) } == ["Hetzner"])
        #expect(hit.author == .you)
        #expect(hit.itemID == nil && hit.isEarlier && hit.date == nil)
    }

    @Test func aMatchFarInStartsTheSnippetNearIt() throws {
        let result = GatewaySearchResult(
            sessionId: "s", lineageRoot: nil, role: "assistant",
            snippet: "All but two. I matched 39 of 41 receipts to the bank statement; the two >>>Hetzner<<< invoices")
        let search = try #require(MessageSearch("hetzner"))
        let hit = try #require(result.hit(in: "ledger", query: search))
        #expect(hit.snippet == "…statement; the two Hetzner invoices")
        #expect(hit.matches.map { String(hit.snippet[$0]) } == ["Hetzner"])
    }

    @Test func onlyYourMessagesAndTheAgentsBecomeHits() throws {
        let search = try #require(MessageSearch("deploy"))
        for role in ["tool", "system", nil] as [String?] {
            let result = GatewaySearchResult(sessionId: "s", lineageRoot: nil, role: role, snippet: ">>>deploy<<<")
            #expect(result.hit(in: "ops", query: search) == nil)
        }
        let reply = GatewaySearchResult(sessionId: "s", lineageRoot: nil, role: "assistant", snippet: ">>>deploy<<<")
        #expect(reply.hit(in: "ops", query: search)?.author == .agent)
    }
}

@MainActor
struct GatewaySearchTests {
    private static let ledgerReply =
        "All but two. I matched 39 of 41 receipts; the two **Hetzner** invoices are missing, so I've asked for copies."

    /// Atlas's chat is loaded whole; Ledger's holds only its last message, as from the offline cache.
    private func model(http: ScriptedHTTP = ScriptedHTTP { _ in (200, "{}") }) -> AppModel {
        let model = AppModel(
            tokenStore: MemoryTokenStore(), http: http, defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        model.contacts = [
            Contact(
                id: "atlas", name: "Atlas", lastActive: Date(timeIntervalSince1970: 1_800_000_000), chatID: "c-atlas"),
            Contact(
                id: "ledger", name: "Ledger", lastActive: Date(timeIntervalSince1970: 1_700_000_000),
                chatID: "c-ledger",
                details: AgentDetails(profile: "ledger")),
        ]
        model.threads["atlas"] = ChatThread.sample(
            "atlas",
            state: ThreadState(
                history: [HistoryMessage(role: "assistant", text: "Hetzner is cheaper", timestamp: 1_800_000_000)],
                running: false))
        let ledger = ChatThread.sample(
            "ledger",
            state: ThreadState(
                history: [
                    HistoryMessage(role: "assistant", text: "October invoices drafted", timestamp: 1_700_000_000)
                ],
                running: false))
        ledger.hasFullHistory = false
        model.threads["ledger"] = ledger
        model.link = .online(.legacy)
        model.gatewaySearch.delay = .zero
        return model
    }

    private func result(_ snippet: String, session: String = "c-ledger", role: String = "assistant")
        -> GatewaySearchResult
    {
        GatewaySearchResult(sessionId: session, lineageRoot: nil, role: role, snippet: snippet)
    }

    @Test func asksOnlyForChatsNotLoadedWholeAndAddsTheirMatchAfterTheDevicesOwn() async throws {
        let model = model()
        let asked = Mutex<[String]>([])
        model.gatewaySearch.fetch = { profile, query in
            asked.withLock { $0.append("\(profile):\(query)") }
            return [
                self.result(">>>Hetzner<<< from Telegram", session: "telegram-chat"),
                self.result("...the two >>>Hetzner<<< invoices are missing..."),
            ]
        }
        model.lookUpMessages("  hetzner ")
        #expect(model.messageSearchStatus("hetzner") == .searching)
        try await waitUntilOnMain { model.messageSearchStatus("hetzner") == .idle }

        #expect(asked.withLock { $0 } == ["ledger:hetzner"])
        let hits = model.searchMessages("hetzner")
        #expect(hits.map(\.contactID) == ["atlas", "ledger"])
        #expect(hits[1].isEarlier)
        #expect(hits[1].snippet == "…the two Hetzner invoices are missing…")
    }

    @Test func aMatchAlreadyFoundOnTheDeviceIsntListedTwice() async throws {
        let model = model()
        model.threads["ledger"]?.replaceTranscript(with: [
            HistoryMessage(role: "assistant", text: Self.ledgerReply, timestamp: 1_600_000_000)
        ])
        model.gatewaySearch.fetch = { _, _ in
            [self.result("I matched 39 of 41 receipts; the two >>>Hetzner<<< invoices are missing, so I've")]
        }
        model.lookUpMessages("hetzner")
        try await waitUntilOnMain { model.messageSearchStatus("hetzner") == .idle }

        let ledgerHits = model.searchMessages("hetzner").filter { $0.contactID == "ledger" }
        #expect(ledgerHits.count == 1)
        #expect(ledgerHits.first?.itemID == 0)
    }

    @Test func aMatchLoadedButPastTheLimitOpensInPlace() async throws {
        let model = model()
        model.threads["ledger"]?.replaceTranscript(with: [
            HistoryMessage(role: "assistant", text: Self.ledgerReply, timestamp: 1_600_000_000)
        ])
        model.gatewaySearch.fetch = { _, _ in [self.result("the two >>>Hetzner<<< invoices are missing")] }
        model.lookUpMessages("hetzner")
        try await waitUntilOnMain { model.messageSearchStatus("hetzner") == .idle }

        // Atlas's newer match fills the device's one place; Ledger's is on the device all the same.
        let hits = model.searchMessages("hetzner", limit: 1)
        #expect(hits.map(\.contactID) == ["atlas", "ledger"])
        #expect(hits[1].itemID == 0)
        #expect(hits[1].date == Date(timeIntervalSince1970: 1_600_000_000))
    }

    @Test func aNewQueryCancelsTheOneBeforeIt() async throws {
        let model = model()
        model.gatewaySearch.delay = .seconds(30)
        let asked = Mutex<[String]>([])
        model.gatewaySearch.fetch = { _, query in
            asked.withLock { $0.append(query) }
            return [self.result(">>>\(query)<<< found")]
        }
        model.lookUpMessages("hetz")
        model.gatewaySearch.delay = .zero
        model.lookUpMessages("hetzner")
        try await waitUntilOnMain { model.messageSearchStatus("hetzner") == .idle }
        #expect(asked.withLock { $0 } == ["hetzner"])

        model.lookUpMessages("x")  // Too short: ends the search.
        #expect(model.gatewaySearch.query == nil)
        #expect(model.searchMessages("hetzner").allSatisfy { !$0.isEarlier })
    }

    @Test func anAnswerToAnOlderQueryIsDropped() async throws {
        let model = model()
        // Not about the pause in typing: its 350 ms ate most of the wait below on a busy runner.
        model.gatewaySearch.delay = .zero
        let (gate, open) = AsyncStream<Void>.makeStream()
        let asked = Mutex<[String]>([])
        model.gatewaySearch.fetch = { _, query in
            asked.withLock { $0.append(query) }
            if query == "alpha" { for await _ in gate { break } }
            return [self.result(">>>\(query)<<< found")]
        }
        model.lookUpMessages("alpha")
        try await waitUntil { asked.withLock { $0 } == ["alpha"] }
        model.lookUpMessages("beta")
        open.yield()
        try await waitUntilOnMain { model.messageSearchStatus("beta") == .idle }
        #expect(model.gatewaySearch.hits["ledger"]?.snippet == "beta found")
        #expect(model.searchMessages("alpha").allSatisfy { !$0.isEarlier })
    }

    @Test func aGatewayWithoutTheEndpointIsAskedOnce() async throws {
        let model = model()
        let calls = Mutex(0)
        model.gatewaySearch.fetch = { _, _ in
            calls.withLock { $0 += 1 }
            throw GatewayError.http(status: 404, message: "Session not found")
        }
        model.lookUpMessages("hetzner")
        try await waitUntilOnMain { model.gatewaySearch.isUnsupported }
        #expect(model.messageSearchStatus("hetzner") == .idle)
        model.lookUpMessages("invoices")
        #expect(model.messageSearchStatus("invoices") == .idle)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func aProfileRemovedMeanwhileDoesntTurnGatewaySearchOff() async throws {
        let model = model()
        model.gatewaySearch.fetch = { _, _ in
            throw GatewayError.http(status: 404, message: "Profile 'ledger' does not exist.")
        }
        model.lookUpMessages("hetzner")
        try await waitUntilOnMain { model.messageSearchStatus("hetzner") == .idle }
        #expect(!model.gatewaySearch.isUnsupported)
    }

    @Test func offlineSearchesTheDeviceOnlyAndSaysSo() {
        let model = model()
        model.link = .offline("Can't reach the gateway.")
        model.gatewaySearch.fetch = { _, _ in
            Issue.record("Asked the gateway while offline")
            return []
        }
        model.lookUpMessages("hetzner")
        #expect(model.messageSearchStatus("hetzner") == .offline)
        #expect(model.messageSearchStatus("h") == .idle)
        #expect(model.searchMessages("hetzner").map(\.contactID) == ["atlas"])
    }

    @Test func callsTheSearchEndpointForTheProfileAndReadsHermessAnswer() async throws {
        let http = ScriptedHTTP { _ in
            (
                200,
                """
                {"results": [
                  {"session_id": "c-ledger", "lineage_root": "c-ledger-root", "profile": "ledger",
                   "snippet": "two >>>Hetzner<<< invoices", "role": "assistant", "source": "desktop",
                   "model": "m", "session_started": 1600000000, "last_active": 1700000000,
                   "title": "Bot Chat", "message_count": 812}
                ]}
                """
            )
        }
        let model = model(http: http)
        model.auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, provider: "p", userID: "u"),
            store: MemoryTokenStore(), http: http)
        model.lookUpMessages("hetzner vat")
        try await waitUntilOnMain { model.messageSearchStatus("hetzner vat") == .idle }

        #expect(
            http.requests.first?.url?.absoluteString
                == "http://100.101.102.103:9119/api/sessions/search?q=hetzner%20vat&profile=ledger&limit=100")
        #expect(model.gatewaySearch.hits["ledger"]?.snippet == "two Hetzner invoices")
    }

    @Test func locatingLoadsTheChatThenFindsTheMessage() async throws {
        let model = model()
        let search = try #require(MessageSearch("hetzner"))
        let hit = try #require(
            result("I matched 39 of 41 receipts; the two >>>Hetzner<<< invoices are missing, so I've")
                .hit(in: "ledger", query: search))
        let thread = try #require(model.threads["ledger"])
        async let location = model.locate(hit)
        // The gateway's copy arrives: the older message, then the one the device had.
        thread.replaceTranscript(with: [
            HistoryMessage(role: "user", text: "Are the receipts in?"),
            HistoryMessage(role: "assistant", text: Self.ledgerReply),
            HistoryMessage(role: "assistant", text: "October invoices drafted"),
        ])
        thread.hasFullHistory = true
        #expect(await location == .item(1))
    }

    @Test func aMessageThatsGoneSaysSo() async throws {
        let model = model()
        model.threads["ledger"]?.hasFullHistory = true
        let search = try #require(MessageSearch("hetzner"))
        let hit = try #require(result(">>>Hetzner<<< invoices are missing").hit(in: "ledger", query: search))
        guard case .unavailable(let reason) = await model.locate(hit) else {
            Issue.record("Found a message that isn't there")
            return
        }
        #expect(reason.contains("Ledger"))
    }

    @Test func theDemoFindsAnOlderLedgerMessageAndOpensIt() async throws {
        let model = AppModel.demo()
        model.gatewaySearch.delay = .zero
        model.gatewaySearch.fetch = { DemoSearch.results(profile: $0, query: $1) }
        model.lookUpMessages("hetzner")
        try await waitUntilOnMain { model.messageSearchStatus("hetzner") == .idle }
        let hit = try #require(model.searchMessages("hetzner").first { $0.contactID == "ledger" })
        #expect(hit.isEarlier)

        guard case .item(let id) = await model.locate(hit) else {
            Issue.record("The demo couldn't open the message")
            return
        }
        let item = try #require(model.threads["ledger"]?.state.items.first { $0.id == id })
        guard case .assistant(let text) = item.content else {
            Issue.record("Not the reply")
            return
        }
        #expect(text.contains("Hetzner"))
    }
}
