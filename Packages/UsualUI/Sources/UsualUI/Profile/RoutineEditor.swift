import HermesKit
import SwiftUI

/// New Routine, or Edit for an existing one: a name, what to do, when, and where results go.
/// The gateway checks the schedule; when it can't read one, its own explanation shows here.
struct RoutineEditor: View {
    let list: RoutineList
    /// `nil` for a new routine.
    let routine: Routine?
    let agentName: String
    /// Back to New Routine's templates; `nil` where it didn't come from them.
    var back: (() -> Void)? = nil
    /// Saved (with the routine) or cancelled (`nil`).
    let done: (Routine?) -> Void

    @State private var draft: RoutineDraft
    @State private var choice: RoutineSchedule.Choice
    @State private var custom: String
    @State private var isSaving = false
    @State private var problem: String?
    /// While you write what to do, Return starts a new line instead of saving.
    @FocusState private var writingPrompt: Bool

    init(
        list: RoutineList, routine: Routine?, agentName: String, back: (() -> Void)? = nil,
        done: @escaping (Routine?) -> Void
    ) {
        self.list = list
        self.routine = routine
        self.agentName = agentName
        self.back = back
        self.done = done
        let draft = routine.map { RoutineDraft($0, profile: list.profile) } ?? RoutineDraft()
        let choice = routine.map { RoutineSchedule.Choice($0.scheduleText) } ?? .init(preset: .daily)
        _draft = State(initialValue: draft)
        _choice = State(initialValue: choice)
        _custom = State(initialValue: choice.preset == .custom ? draft.schedule : "")
    }

    var body: some View {
        SheetForm(
            title: Text(routine == nil ? "New Routine" : "Edit Routine"),
            back: back.map { SheetBack(label: Text("Back to templates"), perform: $0) },
            cancel: { done(nil) },
            action: SheetAction(
                title: routine == nil ? "Create" : "Save", isEnabled: canSave, isDefault: !writingPrompt, perform: save),
            busy: isSaving ? (routine == nil ? "Creating…" : "Saving…") : nil
        ) {
            Form {
                field("Name") {
                    TextField("Name", text: $draft.name, prompt: Text("Optional, like Morning brief"))
                        .textInputTint()
                        .labelsHidden()
                }
                whatToDo
                when
                results
                if let problem {
                    Section {
                        Text(problem)
                            .foregroundStyle(Theme.danger)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        #if os(macOS)
            .frame(width: 460, height: 560)
        #endif
    }

    @ViewBuilder private var whatToDo: some View {
        if let routine, routine.worksWithoutPrompt, routine.prompt.trimmingCharacters(in: .whitespaces).isEmpty {
            field("What to do") {
                Text("This routine runs a script or skills set up in Hermes. Change those in Hermes.")
                    .scaledFont(size: 13.5)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            field("What to do") {
                TextEditor(text: $draft.prompt)
                    .textInputTint()
                    .focused($writingPrompt)
                    .scaledFont(size: 14)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if draft.prompt.isEmpty {
                            // TextEditor has no prompt of its own.
                            Text("Say it as you would to \(agentName), like “Check our dependencies for updates”.")
                                .scaledFont(size: 14)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(Text("What to do"))
            }
        }
    }

    private var when: some View {
        field("When") {
            Picker("Repeats", selection: $choice.preset) {
                ForEach(RoutineSchedule.Preset.allCases) { preset in
                    Text(Self.title(preset)).tag(preset)
                }
            }
            .clickable()
            .pickerStyle(.menu)
            if choice.preset == .weekly {
                Picker("Day", selection: $choice.weekday) {
                    // Monday first, as most calendars here start the week.
                    ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { day in
                        Text(RoutineSchedule.weekdayName(day)).tag(day)
                    }
                }
                .clickable()
                .pickerStyle(.menu)
            }
            if choice.preset.hasTime {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .clickable()
            }
            if choice.preset == .custom {
                VaultTextField(title: "Like every 2h or weekdays at 9am", text: $custom, isLiteral: true)
                Text(
                    "Examples: “every 30m”, “every monday 9am”, “weekdays at 9am”, a cron expression like “0 9 * * 1-5”, or once with “in 2h”."
                )
                .scaledFont(size: 12)
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            } else if let expression = choice.expression {
                Text(RoutineSchedule.plainWords(expression))
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
    }

    private var results: some View {
        field("Results") {
            Picker("Results", selection: $draft.delivery) {
                Text("Post in this chat").tag(RoutineDelivery.thisChat)
                Text("Keep in past runs only").tag(RoutineDelivery.pastRunsOnly)
                if let original, case .elsewhere(let raw) = original {
                    Text("Keep sending to \(RoutineDelivery.places(raw, profile: list.profile))").tag(original)
                }
            }
            .clickable()
            .labelsHidden()
            // Radio buttons on the Mac; iPhone has none, so a menu there.
            #if os(macOS)
                .pickerStyle(.radioGroup)
            #else
                .pickerStyle(.menu)
            #endif
            Text(resultsHint)
                .scaledFont(size: 12)
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var original: RoutineDelivery? {
        routine.map { RoutineDelivery(deliver: $0.deliver, profile: list.profile) }
    }

    private var resultsHint: String {
        switch draft.delivery {
        case .thisChat:
            String(localized: "\(agentName) gets the result as a message here and replies to it, which uses a turn.")
        case .pastRunsOnly:
            String(localized: "Nothing is posted. Open the routine to read each run.")
        case .elsewhere:
            String(localized: "Set up in Hermes. Usual Bot leaves it as it is.")
        }
    }

    private var schedule: String { choice.expression ?? custom }

    private var canSave: Bool {
        var filled = draft
        filled.schedule = schedule
        return filled.isComplete(editing: routine) && !isSaving
    }

    /// The preset's time of day, for the time picker.
    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: choice.hour, minute: choice.minute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            choice.hour = parts.hour ?? choice.hour
            choice.minute = parts.minute ?? choice.minute
        }
    }

    private func save() {
        guard canSave else { return }
        var filled = draft
        filled.schedule = schedule
        isSaving = true
        problem = nil
        Task {
            defer { isSaving = false }
            do {
                if let routine {
                    done(try await list.save(filled, to: routine))
                } else {
                    done(try await list.create(filled))
                }
            } catch {
                // The form stays as typed, to fix and save again.
                problem = RoutineList.describe(error)
            }
        }
    }

    private func field(_ label: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        Section {
            content()
        } header: {
            Text(label)
        }
    }

    private static func title(_ preset: RoutineSchedule.Preset) -> LocalizedStringKey {
        switch preset {
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Every week"
        case .monthly: "Every month, on the 1st"
        case .hourly: "Every hour"
        case .every15Minutes: "Every 15 minutes"
        case .custom: "Custom"
        }
    }
}
