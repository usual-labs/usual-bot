import HermesKit
import SwiftUI

/// One template's questions, with the schedule they make and where results go. Hermes writes the
/// instructions from the answers when it creates the routine; they can be changed straight after.
struct RoutineTemplateForm: View {
    let list: RoutineList
    let template: RoutineTemplate
    let agentName: String
    let back: () -> Void
    let cancel: () -> Void
    let created: (TemplateRoutine) -> Void

    @State private var values: [String: String]
    @State private var delivery = RoutineDelivery.thisChat
    @State private var isSaving = false
    @State private var problem: String?
    /// Fields changed here: a blank one says it's needed only once someone has been at it.
    @State private var touched: Set<String> = []

    init(
        list: RoutineList, template: RoutineTemplate, agentName: String, back: @escaping () -> Void,
        cancel: @escaping () -> Void, created: @escaping (TemplateRoutine) -> Void
    ) {
        self.list = list
        self.template = template
        self.agentName = agentName
        self.back = back
        self.cancel = cancel
        self.created = created
        _values = State(initialValue: template.defaults)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: back) {
                    Label("Templates", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.clickable)
                .accessibilityLabel(Text("Back to templates"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: template.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: template.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(template.questions) { field in
                    question(field)
                }
                schedule
                if template.hasDelivery { results }
                Text(
                    "\(agentName) gets instructions written from your answers. You can read and change them once it's created."
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                if let problem {
                    Text(problem)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.danger)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Cancel", action: cancel)
                        .buttonStyle(CardButtonStyle(primary: false))
                        .keyboardShortcut(.cancelAction)
                    Button(isSaving ? "Creating…" : "Create", action: create)
                        .buttonStyle(CardButtonStyle(primary: true))
                        .disabled(!canCreate)
                        .opacity(canCreate ? 1 : 0.4)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 340, idealWidth: 460, maxWidth: 560, minHeight: 460)
        .background(Theme.window)
    }

    private func question(_ field: RoutineTemplate.Field) -> some View {
        let value = binding(field.name)
        let blankAtStart = field.defaultValue.isEmpty && !touched.contains(field.name)
        let problem = blankAtStart ? nil : field.problem(with: value.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: field.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityHidden(true)
            switch field.kind {
            case .time:
                DatePicker(selection: time(value), displayedComponents: .hourAndMinute) {
                    Text(verbatim: field.label)
                }
                .labelsHidden()
                .fixedSize()
            case .choice, .days:
                Picker(selection: value) {
                    // The current value stays a choice even if the list leaves it out.
                    ForEach(choices(field, current: value.wrappedValue), id: \.self) { option in
                        Text(verbatim: field.title(for: option)).tag(option)
                    }
                } label: {
                    Text(verbatim: field.label)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            case .text:
                TextField(text: value, prompt: Text(verbatim: Self.sentence(field.help))) {
                    Text(verbatim: field.label)
                }
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Theme.pane, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).strokeBorder(problem == nil ? Theme.border : Theme.danger))
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
            } else if !field.help.isEmpty, field.kind != .time {
                Text(verbatim: Self.sentence(field.help))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(field.kind == .text)  // Already the field's prompt.
            }
        }
    }

    /// The schedule the answers make, in words.
    @ViewBuilder private var schedule: some View {
        if let expression = template.schedule(values) {
            let words = RoutineSchedule.plainWords(expression)
            // A cron expression the app can't put in words says nothing useful here.
            if words != expression {
                VStack(alignment: .leading, spacing: 3) {
                    Text("When")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryInk)
                    Text(words)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Results")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            Picker("Results", selection: $delivery) {
                Text("Post in this chat").tag(RoutineDelivery.thisChat)
                Text("Keep in past runs only").tag(RoutineDelivery.pastRunsOnly)
            }
            .labelsHidden()
            #if os(macOS)
                .pickerStyle(.radioGroup)
            #else
                .pickerStyle(.menu)
                .fixedSize()
            #endif
        }
    }

    private var canCreate: Bool { template.isComplete(values) && !isSaving }

    private func create() {
        isSaving = true
        problem = nil
        Task {
            defer { isSaving = false }
            do {
                created(try await list.create(from: template, values: values, delivery: delivery))
            } catch {
                // The answers stay as typed, to fix and create again.
                problem = RoutineList.describe(error)
            }
        }
    }

    private func binding(_ name: String) -> Binding<String> {
        Binding {
            values[name] ?? ""
        } set: { value in
            // A Mac text field writes its value back when it takes focus: that isn't a change.
            guard value != values[name] ?? "" else { return }
            values[name] = value
            touched.insert(name)
        }
    }

    private func choices(_ field: RoutineTemplate.Field, current: String) -> [String] {
        field.options.contains(current) || current.isEmpty ? field.options : [current] + field.options
    }

    /// An "HH:MM" value for the time picker.
    private func time(_ value: Binding<String>) -> Binding<Date> {
        Binding {
            let parts = value.wrappedValue.split(separator: ":").compactMap { Int($0) }
            let (hour, minute) = parts.count == 2 ? (parts[0], parts[1]) : (9, 0)
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            value.wrappedValue = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
    }

    /// Hermes's help is lower case and unpunctuated, like "hours between checks".
    private static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
