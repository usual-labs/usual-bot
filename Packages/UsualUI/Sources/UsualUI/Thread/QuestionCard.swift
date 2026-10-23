import HermesKit
import SwiftUI

/// The agent's questions, answered in the chat: pick a suggestion or type your own answer.
struct QuestionCard: View {
    let prompt: ClarifyPrompt
    let agentName: String
    let answer: ([String: [String]]) -> Void
    let skip: () -> Void

    @State private var picked: [String: [String]] = [:]
    @State private var typed: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(prompt.questions.count == 1 ? "\(agentName) has a question" : "\(agentName) has some questions")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: "questionmark.bubble")
                    .foregroundStyle(Theme.needsYouInk)
            }
            ForEach(prompt.questions) { question in
                questionView(question)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Skip", action: skip)
                    .buttonStyle(CardButtonStyle(primary: false))
                Button("Send") { answer(answers) }
                    .buttonStyle(CardButtonStyle(primary: true))
                    .disabled(!isComplete)
                    .opacity(isComplete ? 1 : 0.4)
            }
        }
        .padding(14)
        .frame(maxWidth: 540)
        .background(Theme.pane, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func questionView(_ question: ClarifyPrompt.Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.text)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(question.choices, id: \.self) { choice in
                let isPicked = picked[question.id, default: []].contains(choice)
                Button {
                    toggle(choice, in: question)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: indicator(isPicked, multiple: question.allowsMultiple))
                            .foregroundStyle(isPicked ? Theme.ink : Theme.secondaryInk)
                        Text(choice)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(isPicked ? Theme.selection : Theme.codeFill, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
            TextField(
                question.choices.isEmpty ? "Your answer" : "Or type your own answer",
                text: Binding(
                    get: { typed[question.id, default: ""] },
                    set: { typed[question.id] = $0 }), axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .lineLimit(1...4)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.pane, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        }
    }

    private func indicator(_ isPicked: Bool, multiple: Bool) -> String {
        if multiple { return isPicked ? "checkmark.square.fill" : "square" }
        return isPicked ? "largecircle.fill.circle" : "circle"
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

/// The pill buttons used on approval and question cards.
struct CardButtonStyle: ButtonStyle {
    let primary: Bool
    /// Takes the full width, for buttons stacked in a narrow card.
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? Theme.primaryInk : Theme.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: fill ? 40 : 34)
            .background(primary ? Theme.primary : Color.clear, in: Capsule())
            .overlay { if !primary { Capsule().strokeBorder(Theme.border) } }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
