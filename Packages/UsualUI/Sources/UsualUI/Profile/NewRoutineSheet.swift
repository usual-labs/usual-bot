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
                // Back to the templates, unless the gateway has none to go back to.
                RoutineEditor(
                    list: list, routine: nil, agentName: agentName,
                    back: list.templatePhase == .unavailable ? nil : { page = .choose }
                ) { _ in done() }
            case .template(let template):
                RoutineTemplateForm(
                    list: list, template: template, agentName: agentName, back: { page = .choose },
                    cancel: done, created: { page = .created($0) })
            case .created(let made):
                RoutineDetail(list: list, id: made.routine.id, agentName: agentName, created: made)
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
        SheetForm(title: Text("New Routine"), cancel: done) {
            Form {
                Section {
                    ChoiceRow(
                        icon: "square.and.pencil", title: Text("Start from scratch"),
                        summary: String(localized: "Say what \(agentName) should do and when.")
                    ) { page = .blank }
                }
                Section("Templates") {
                    if list.templatePhase == .loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading templates…")
                        }
                        .foregroundStyle(Theme.secondaryInk)
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(list.templates) { template in
                        ChoiceRow(
                            icon: Self.icon(template.category), title: Text(verbatim: template.title),
                            summary: template.summary
                        ) { page = .template(template) }
                    }
                }
            }
        }
        #if os(macOS)
            .frame(width: 460, height: 560)
        #endif
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

    /// A phone's narrow sheet cuts one line short after a few words.
    #if os(iOS)
        private static let summaryLines = 2
    #else
        private static let summaryLines = 1
    #endif

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Theme.ink)
                    Text(summary)
                        .scaledFont(size: 12.5)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(Self.summaryLines)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            // On the label, not the button: wrapping the button made an element VoiceOver couldn't
            // press.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            // The whole line, which the row cuts short.
            .accessibilityValue(Text(summary))
        }
        // A row that opens the next page, as a list's navigation row: no button chrome.
        .buttonStyle(.clickable)
    }
}

/// Above a routine just made from a template: that it's made, to look it over, and any skill it
/// uses that the agent can't load.
struct CreatedFromTemplate: View {
    let made: TemplateRoutine
    let agentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Created. Look over what it does below, and use Edit to change anything.", systemImage: "checkmark")
                .scaledFont(size: 13)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(made.missingSkills, id: \.name) { skill in
                Label(Self.advice(skill, agentName: agentName), systemImage: "exclamationmark.triangle")
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.needsYouInk)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.needsYouFill, in: RoundedRectangle(cornerRadius: 10))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
