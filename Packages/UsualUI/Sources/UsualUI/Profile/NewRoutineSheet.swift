import HermesKit
import SwiftUI

/// New Routine: start from scratch or from one of the gateway's templates. A gateway without
/// templates, or one that can't be reached for them, goes straight to the blank form.
struct NewRoutineSheet: View {
    private enum Page: Equatable {
        case choose
        case blank
        case template(RoutineTemplate)
        /// Made from a template: the routine as Hermes filled it in, to look over and change.
        case created(TemplateRoutine)
    }

    let list: RoutineList
    let agentName: String
    let done: () -> Void

    @State private var page: Page

    init(list: RoutineList, agentName: String, done: @escaping () -> Void) {
        self.list = list
        self.agentName = agentName
        self.done = done
        _page = State(initialValue: Self.start(list))
        #if DEBUG
            // `USUALBOT_OPEN_ROUTINE=new/<template key>` opens that template's form.
            if let key = RoutinesView.launchRoute?.dropFirst().first,
                let template = list.templates.first(where: { $0.key == key })
            {
                _page = State(initialValue: .template(template))
            }
        #endif
    }

    var body: some View {
        Group {
            switch page {
            case .choose: chooser
            case .blank:
                RoutineEditor(list: list, routine: nil, agentName: agentName) { _ in done() }
            case .template(let template):
                RoutineTemplateForm(
                    list: list, template: template, agentName: agentName, back: { page = .choose },
                    cancel: done, created: { page = .created($0) })
            case .created(let made):
                VStack(spacing: 0) {
                    CreatedFromTemplate(made: made, agentName: agentName)
                    RoutineDetail(list: list, id: made.routine.id, agentName: agentName)
                }
            }
        }
        // Templates that turn out to be missing leave only the blank form to show.
        .onChange(of: list.templatePhase) { _, phase in
            if page == .choose, phase == .unavailable { page = .blank }
        }
    }

    private static func start(_ list: RoutineList) -> Page {
        list.templatePhase == .unavailable ? .blank : .choose
    }

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("New Routine")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button("Cancel", action: done)
                        .buttonStyle(CardButtonStyle(primary: false))
                        .keyboardShortcut(.cancelAction)
                }
                ChoiceRow(
                    icon: "square.and.pencil", title: Text("Start from scratch"),
                    summary: String(localized: "Say what \(agentName) should do and when.")
                ) { page = .blank }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Templates")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryInk)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 4)
                    if list.templatePhase == .loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading templates…")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(list.templates) { template in
                        ChoiceRow(
                            icon: Self.icon(template.category), title: Text(verbatim: template.title),
                            summary: template.summary
                        ) { page = .template(template) }
                        Divider().overlay(Theme.border)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 340, idealWidth: 460, maxWidth: 560, minHeight: 460)
        .background(Theme.window)
        .task { await list.loadTemplates() }
    }

    /// Hermes's categories; plugins may bring others.
    private static func icon(_ category: String) -> String {
        switch category {
        case "daily": "sun.max"
        case "weekly": "calendar"
        case "email": "envelope"
        default: "sparkles"
        }
    }
}

/// A way to start: an icon, a title and one line about it.
private struct ChoiceRow: View {
    let icon: String
    let title: Text
    let summary: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.pane, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clickable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        // The whole line, which the row cuts short.
        .accessibilityValue(Text(summary))
        .accessibilityAddTraits(.isButton)
    }
}

/// Above a routine just made from a template: that it's made, to look it over, and any skill it
/// uses that the agent can't load.
private struct CreatedFromTemplate: View {
    let made: TemplateRoutine
    let agentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Created. Look over what it does below, and use Edit to change anything.", systemImage: "checkmark")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(made.missingSkills, id: \.name) { skill in
                Label(Self.advice(skill, agentName: agentName), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.needsYouInk)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.needsYouFill, in: RoundedRectangle(cornerRadius: 10))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.window)
    }

    /// Hermes skips a skill it can't load and runs without it, so say that and how to fix it.
    static func advice(_ skill: TemplateRoutine.MissingSkill, agentName: String) -> String {
        skill.isOff
            ? String(
                localized:
                    "It uses the “\(skill.name)” skill, which is turned off for \(agentName). Turn it on under Skills, or it runs without it."
            )
            : String(
                localized:
                    "It uses the “\(skill.name)” skill, which \(agentName) doesn't have. Add it in Hermes, or it runs without it."
            )
    }
}
