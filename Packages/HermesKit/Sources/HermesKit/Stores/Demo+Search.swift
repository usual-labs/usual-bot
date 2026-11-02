#if DEBUG
    import Foundation

    /// The demo's pretend gateway search: Ledger's chat holds only its last message, and searching
    /// "Hetzner" finds an older one that opening the result loads.
    enum DemoSearch {
        /// Ledger's chat from weeks ago, which only the pretend gateway holds at first.
        static let ledgerEarlier = [
            HistoryMessage(role: "user", text: "Are all the September receipts in for the VAT return?"),
            HistoryMessage(
                role: "assistant",
                text: """
                    All but two. I matched 39 of 41 receipts to the bank statement; the two **Hetzner** \
                    invoices are missing, so I've asked their billing team for copies.
                    """),
            HistoryMessage(role: "user", text: "Thanks. File the return once they arrive."),
        ]

        /// Leaves Ledger's chat holding only its last message, like a chat not loaded yet.
        @MainActor static func holdBack(_ thread: ChatThread?, now: Date) {
            guard let thread else { return }
            let start = now.addingTimeInterval(-40 * 86_400).timeIntervalSince1970
            thread.hasFullHistory = false
            thread.demoFullHistory =
                ledgerEarlier.enumerated().map { index, message in
                    HistoryMessage(role: message.role, text: message.text, timestamp: start + Double(index) * 90)
                } + [
                    HistoryMessage(
                        role: "assistant", text: "October invoices are drafted for review",
                        timestamp: now.addingTimeInterval(-26 * 3600).timeIntervalSince1970)
                ]
        }

        /// `GET /api/sessions/search` for one profile: Ledger's Hetzner message, its matches marked
        /// as FTS5 marks them, when it holds every word of the query.
        static func results(profile: String, query: String) -> [GatewaySearchResult] {
            guard profile == "ledger", let search = MessageSearch(query), let message = ledgerEarlier[1].text,
                search.matches(folded: Array(MessageSearch.fold(MessageSearch.plain(message)).utf8))
            else { return [] }
            let words = message.split(separator: " ").map { word in
                let folded = MessageSearch.fold(String(word))
                return search.words.contains { folded.contains($0) } ? ">>>\(word)<<<" : String(word)
            }
            return [
                GatewaySearchResult(
                    sessionId: "demo-ledger", lineageRoot: "demo-ledger", role: "assistant",
                    snippet: words.joined(separator: " "))
            ]
        }
    }

    extension ChatThread {
        /// The demo's stand-in for attaching to the gateway: after a moment, the whole history
        /// replaces the last messages.
        func loadDemoHistory() async {
            guard let history = demoFullHistory else { return }
            demoFullHistory = nil
            // sleep-ok: a long chat takes a moment to load, so "Finding the message" shows.
            try? await Task.sleep(for: .milliseconds(700))
            replaceTranscript(with: history)
            hasFullHistory = true
        }
    }
#endif
