import HermesKit
import SwiftUI

/// A side question (`/btw`) and its answer, above the message box: the agent keeps working and
/// the answer stays out of the conversation. The ✕ dismisses it.
struct SideQuestionCard: View {
    let question: SideQuestion
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Side question")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Theme.secondaryInk)
                Text(question.question)
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1, accessibility: 3)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .touchTarget(width: 22, height: 22)
                }
                .buttonStyle(.clickable(.borderless))
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Dismiss the side question"))
            }
            switch question.answer {
            case .waiting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking on the side…")
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.secondaryInk)
                }
            case .answered(let text):
                ScrollView {
                    MarkdownView(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .thinScroller()
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text("Couldn't answer: \(message)")
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // It floats over the transcript, above the message box.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The background tasks (`/bg`) still running, as one bar above the message box: the task when
/// there's one, a count and their names when there are more. Each answer joins the chat.
struct BackgroundTasksBar: View {
    let tasks: [HermesKit.BackgroundTask]

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(summary)
                .scaledFont(size: 12.5)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1, accessibility: 3)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .glassEffect(.regular, in: Capsule())
        .help(tasks.map(\.task).joined(separator: "\n"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary))
    }

    private var summary: String {
        let names = tasks.map(\.task)
        guard names.count > 1 else { return String(localized: "Working in the background: \(names.first ?? "")") }
        return String(localized: "\(names.count) tasks working in the background: \(names.joined(separator: " · "))")
    }
}
