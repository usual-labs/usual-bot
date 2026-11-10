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
        SheetForm(
            title: Text(verbatim: template.title),
            back: SheetBack(label: Text("Back to templates"), perform: back),
            cancel: cancel,
            action: SheetAction(title: "Create", isEnabled: canCreate, perform: create),
            busy: isSaving ? "Creating…" : nil
        ) {
            Form {
                Section {
                    ForEach(template.questions) { field in
                        question(field)
                    }
                } header: {
                    Text(verbatim: template.summary)
                        .textCase(nil)
                        .font(.subheadline)
                }
                schedule
                if template.hasDelivery { results }
                Section {
                    if let problem {
                        Text(problem)
                            .foregroundStyle(Theme.danger)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text(
                        "\(agentName) gets instructions written from your answers. You can read and change them once it's created."
                    )
                }
            }
        }
        #if os(macOS)
            .frame(width: 460, height: 520)
        #endif
    }

    /// A row per question: its label and control, with what's wrong or what it's for under it.
    private func question(_ field: RoutineTemplate.Field) -> some View {
        let value = binding(field.name)
        let blankAtStart = field.defaultValue.isEmpty && !touched.contains(field.name)
        let problem = blankAtStart ? nil : field.problem(with: value.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            switch field.kind {
            case .time:
                DatePicker(selection: time(value), displayedComponents: .hourAndMinute) {
                    Text(verbatim: field.label)
                }
                .clickable()
            case .choice, .days:
                Picker(selection: value) {
                    // The current value stays a choice even if the list leaves it out.
                    ForEach(choices(field, current: value.wrappedValue), id: \.self) { option in
                        Text(verbatim: field.title(for: option)).tag(option)
                    }
                } label: {
                    Text(verbatim: field.label)
                }
                .clickable()
                .pickerStyle(.menu)
            case .text:
                #if os(iOS)
                    // An iPhone form shows a field's prompt, not its label, so the label goes above.
                    Text(verbatim: field.label)
                        .accessibilityHidden(true)
                    TextField(text: value, prompt: Text(verbatim: Self.sentence(field.help))) {
                        Text(verbatim: field.label)
                    }
                    .textInputTint()
                #else
                    TextField(text: value, prompt: Text(verbatim: Self.sentence(field.help))) {
                        Text(verbatim: field.label)
                    }
                    .textInputTint()
                #endif
            }
            if let problem {
                Text(problem)
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.danger)
            } else if !field.help.isEmpty, field.kind != .time, field.kind != .text || !value.wrappedValue.isEmpty {
                // A blank field's prompt already says it.
                Text(verbatim: Self.sentence(field.help))
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The schedule the answers make, in words.
    @ViewBuilder private var schedule: some View {
        if let expression = template.schedule(values) {
            let words = RoutineSchedule.plainWords(expression)
            // A cron expression the app can't put in words says nothing useful here.
            if words != expression {
                Section {
                    LabeledContent("When", value: words)
                }
            }
        }
    }

    private var results: some View {
        Section {
            Picker("Results", selection: $delivery) {
                Text("Post in this chat").tag(RoutineDelivery.thisChat)
                Text("Keep in past runs only").tag(RoutineDelivery.pastRunsOnly)
            }
            .clickable()
            #if os(macOS)
                .pickerStyle(.radioGroup)
            #else
                .pickerStyle(.menu)
            #endif
        }
    }

    private var canCreate: Bool { template.isComplete(values) && !isSaving }

    private func create() {
        guard canCreate else { return }
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
