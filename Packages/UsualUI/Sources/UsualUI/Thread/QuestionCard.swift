import HermesKit
import SwiftUI

/// The agent's questions, answered in the chat: pick a suggestion or type your own answer.
///
/// One question with one answer takes Grok's lighter card: a choice answers at once, ✕ skips, and
/// the message box below answers in your own words. Anything more keeps a form with Send.
struct QuestionCard: View {
    let prompt: ClarifyPrompt
    let agentName: String
    let answer: ([String: [String]]) -> Void
    let skip: () -> Void
    /// The message box answers this question, so the card needs no field or Send.
    var answersFromBox = false

    @Environment(\.messageTextSize) private var messageSize
    @ScaledMetric(relativeTo: .body) private var scaledChip: CGFloat = 24
    @State private var picked: [String: [String]] = [:]
    @State private var typed: [String: String] = [:]

    var body: some View {
        if answersFromBox, let question = prompt.questions.first {
            light(question)
        } else {
            form
        }
    }

    private func light(_ question: ClarifyPrompt.Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    title(question)
                    Spacer(minLength: 0)
                    Button(action: skip) {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .touchTarget(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Skip the question"))
                    .help("Skip")
                }
                ForEach(Array(question.choices.enumerated()), id: \.element) { index, choice in
                    choiceButton(index, choice, isPicked: false) { answer([question.id: [choice]]) }
                }
            }
            .cardSurface()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(agentName) has a question"))
            Text("Or answer in the chat below")
                .scaledFont(size: 13)
                .foregroundStyle(Theme.secondaryInk)
                .padding(.leading, 14)
        }
    }

    private func title(_ question: ClarifyPrompt.Question) -> some View {
        Text(question.text)
            .font(.system(size: messageSize, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func choiceButton(
        _ index: Int, _ choice: String, isPicked: Bool, action: @escaping () -> Void
    ) -> some View {
        // A full-width bordered button per choice, its letter leading, as a list of options.
        Button(action: action) {
            HStack(spacing: 10) {
                letterChip(index, isPicked: isPicked)
                Text(choice)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: messageSize))
        }
        .cardButton()
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(prompt.questions) { question in
                questionView(question)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Skip", action: skip)
                    .cardButton()
                Button("Send") { answer(answers) }
                    .cardButton(prominent: true)
                    .disabled(!isComplete)
            }
        }
        .cardSurface()
        .accessibilityLabel(
            Text(prompt.questions.count == 1 ? "\(agentName) has a question" : "\(agentName) has some questions"))
    }

    private func questionView(_ question: ClarifyPrompt.Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title(question)
            ForEach(Array(question.choices.enumerated()), id: \.element) { index, choice in
                let isPicked = picked[question.id, default: []].contains(choice)
                choiceButton(index, choice, isPicked: isPicked) { toggle(choice, in: question) }
            }
            TextField(
                question.choices.isEmpty ? "Your answer" : "Or type your own answer",
                text: Binding(
                    get: { typed[question.id, default: ""] },
                    set: { typed[question.id] = $0 }), axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .scaledFont(size: 14)
            .lineLimit(1...4)
        }
    }

    /// Grows with the text beside it, but stays a badge.
    private var chipSize: CGFloat { min(scaledChip, 40) }

    /// A, B, C… for a choice, filled when it's picked. Past Z, the number. Round, as a list
    /// marker: an outlined square read as a key to press, and typing a letter mustn't answer
    /// (your own answer in the box can start with one).
    private func letterChip(_ index: Int, isPicked: Bool) -> some View {
        Text(verbatim: index < 26 ? String(UnicodeScalar(UInt8(65 + index))) : "\(index + 1)")
            .font(.system(size: chipSize / 2, weight: .semibold))
            .foregroundStyle(isPicked ? Theme.primaryInk : Theme.secondaryInk)
            .frame(width: chipSize, height: chipSize)
            .background(isPicked ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(.background), in: Circle())
            .accessibilityHidden(true)
    }

    private func toggle(_ choice: String, in question: ClarifyPrompt.Question) {
        var current = picked[question.id, default: []]
        if let index = current.firstIndex(of: choice) {
            current.remove(at: index)
        } else {
            current = question.allowsMultiple ? current + [choice] : [choice]
            if !question.allowsMultiple { typed[question.id] = "" }
        }
        picked[question.id] = current
    }

    /// Typed text replaces a single choice and adds to multiple ones.
    private var answers: [String: [String]] {
        var result: [String: [String]] = [:]
        for question in prompt.questions {
            let own = typed[question.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            let chosen = picked[question.id, default: []]
            if own.isEmpty {
                result[question.id] = chosen
            } else {
                result[question.id] = question.allowsMultiple ? chosen + [own] : [own]
            }
        }
        return result
    }

    private var isComplete: Bool {
        prompt.questions.allSatisfy { !(answers[$0.id] ?? []).isEmpty }
    }
}

/// The pill buttons cards used before they took the system's bordered buttons (`cardButton`).
struct CardButtonStyle: ButtonStyle {
    let primary: Bool
    /// Takes the full width, for buttons stacked in a narrow card.
    var fill = false

    /// iPhone's buttons, and a question's choices, are at least a fingertip tall.
    #if os(iOS)
        static let rowHeight: CGFloat = 44
        static let fillHeight: CGFloat = 44
    #else
        static let rowHeight: CGFloat = 34
        static let fillHeight: CGFloat = 40
    #endif

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(size: 13.5, weight: primary ? .semibold : .regular)
            .foregroundStyle(primary ? Theme.primaryInk : Theme.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: fill ? Self.fillHeight : Self.rowHeight)
            .background(primary ? Theme.primary : Color.clear, in: Capsule())
            .overlay { if !primary { Capsule().strokeBorder(Theme.border) } }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
            .clickable()
    }
}
