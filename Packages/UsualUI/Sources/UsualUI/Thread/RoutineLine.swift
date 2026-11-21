import HermesKit
import SwiftUI

/// A routine's output, posted in its Bot's chat: a message from the Bot with the routine's name
/// over it. It used to be a folded line like a background command's, and a morning brief or a
/// list to act on went unread for days behind it. A long one shows its start with Show All; one
/// with nothing in it is only its line.
struct RoutineLine: View {
    let item: TranscriptItem
    let name: String
    let output: String
    let agentName: String

    private var label: String { TranscriptItem.Content.routineLabel(name) }

    var body: some View {
        if output.isEmpty {
            FoldedRow(symbol: "clock", opens: false) {
                Text(label).lineLimit(1)
            } rows: {
                EmptyView()
            }
        } else {
            MessageRow(item: item, text: output, author: label, agentName: agentName, isMine: false, readsAloud: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(label).lineLimit(2)
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .scaledFont(size: 12.5, weight: .medium)
                    .foregroundStyle(Theme.secondaryInk)
                    AgentBubble { ReportPeek(text: output, style: .markdown, inset: 0) }
                }
            }
        }
    }
}
