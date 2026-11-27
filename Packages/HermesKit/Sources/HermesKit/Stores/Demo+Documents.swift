#if DEBUG
    import CoreGraphics
    import CoreText
    import Foundation

    /// The demo's documents, for the file viewer: the spec you sent Forge, Atlas's plan, Scribe's
    /// draft in the room and Ledger's invoices. All made up; the PDF is drawn here.
    enum DemoDocuments {
        static let specPath = "attachments/search-spec.md"
        static let trialPlanPath = "/home/hermes/.hermes/profiles/atlas/docs/search/turbopuffer-trial.md"
        static let launchPostPath = "/home/hermes/.hermes/profiles/scribe/drafts/launch-post.md"
        static let invoicesPath = "/home/hermes/.hermes/profiles/ledger/invoices/october-2026.pdf"

        static let ledgerReply = "October invoices are drafted for review.\nMEDIA:\(invoicesPath)"

        static var files: [String: Data] {
            var files = [specPath: spec, trialPlanPath: trialPlan, launchPostPath: launchPost].mapValues {
                Data($0.utf8)
            }
            files[invoicesPath] = invoices()
            return files
        }

        private static let spec = """
            # Search index

            Docs search should find a page as you type, in under 300 ms.

            ## What changes

            - Add a GIN index on `pages.body_tsv`.
            - Backfill it in batches of 5,000 rows, so the database stays responsive.
            - Keep the current search as the fallback.

            ## Done when

            1. The migration runs on staging without locking `pages`.
            2. `npm test -- search` passes.
            """

        private static let trialPlan = """
            # Turbopuffer trial

            A two-week trial behind the existing search box, with the current search as the fallback.

            ## Plan

            1. **Index nightly.** Forge exports the 40,000 docs pages to Turbopuffer at 02:00.
            2. **Query it first.** Search asks Turbopuffer, and falls back to the current search if it \
            errors or takes over 300 ms.
            3. **Compare.** Each day, log which search answered and how fast.

            ## Cost

            | | Per month |
            | --- | ---: |
            | Storage | ~$4 |
            | Queries | ~$2 |

            > If the fallback answers more than 5% of searches, we stop the trial and look again.
            """

        private static let launchPost = """
            # Search that keeps up

            Docs search now finds the page you want as you type. Start typing a word from the page, \
            not its title, and it's there before you finish.

            ## What's new

            - Results appear in under a third of a second.
            - Search reads the whole page, not just its title.
            - If the new search ever stumbles, the old one answers instead.

            Try it from the search box at the top of any page.
            """

        /// Ledger's invoice summary: one page, drawn with Core Graphics and Core Text.
        static func invoices() -> Data? {
            let data = NSMutableData()
            var page = CGRect(x: 0, y: 0, width: 595, height: 842)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                let context = CGContext(consumer: consumer, mediaBox: &page, nil)
            else { return nil }
            context.beginPDFPage(nil)
            let ink = CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
            let grey = CGColor(red: 0.45, green: 0.46, blue: 0.5, alpha: 1)
            func draw(_ text: String, size: CGFloat, bold: Bool = false, color: CGColor, x: CGFloat, y: CGFloat) {
                let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
                let string = NSAttributedString(
                    string: text,
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                    ])
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(string), context)
            }
            draw("October 2026 invoices", size: 24, bold: true, color: ink, x: 56, y: 760)
            draw("Drafted by Ledger for review. Nothing has been sent.", size: 11, color: grey, x: 56, y: 736)
            let rows = [
                ("INV-1041", "Northwind Traders", "$4,200.00"),
                ("INV-1042", "Example Analytics", "$1,850.00"),
                ("INV-1043", "Contoso Design", "$960.00"),
                ("INV-1044", "Fabrikam Labs", "$3,120.00"),
            ]
            draw("Invoice", size: 11, bold: true, color: grey, x: 56, y: 690)
            draw("Client", size: 11, bold: true, color: grey, x: 150, y: 690)
            draw("Amount", size: 11, bold: true, color: grey, x: 460, y: 690)
            context.setFillColor(CGColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1))
            context.fill(CGRect(x: 56, y: 680, width: 483, height: 1))
            for (index, row) in rows.enumerated() {
                let y = 656 - CGFloat(index) * 28
                draw(row.0, size: 12, color: ink, x: 56, y: y)
                draw(row.1, size: 12, color: ink, x: 150, y: y)
                draw(row.2, size: 12, color: ink, x: 460, y: y)
            }
            context.fill(CGRect(x: 56, y: 536, width: 483, height: 1))
            draw("Total", size: 12, bold: true, color: ink, x: 150, y: 512)
            draw("$10,130.00", size: 12, bold: true, color: ink, x: 460, y: 512)
            draw("Due 30 November 2026. Payment details are on each invoice.", size: 11, color: grey, x: 56, y: 470)
            context.endPDFPage()
            context.closePDF()
            return data as Data
        }
    }
#endif
