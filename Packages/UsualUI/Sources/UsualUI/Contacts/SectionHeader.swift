import CoreTransferable
import HermesKit
import SwiftUI
import UniformTypeIdentifiers

/// A section's heading in the sidebar. Click it to fold the section; a folded heading shows what
/// its hidden rows would, so nothing waiting for you goes out of sight. A section's actions are a
/// context menu on the Mac. On iPhone, as in Grok, a tap folds and touch and hold opens them: a list
/// header can't have a context menu, so the heading is a menu whose tap folds.
struct SectionHeader<Actions: View>: View {
    let title: String
    let block: SidebarBlock
    let isFolded: Bool
    let toggle: () -> Void
    @ViewBuilder let actions: () -> Actions

    @State private var isHovering = false

    var body: some View {
        #if os(macOS)
            foldButton
                .onHover { isHovering = $0 }
                .contextMenu { actions() }
        #else
            if block.section != nil {
                Menu(content: actions) {
                    label
                } primaryAction: {
                    toggle()
                }
                // A menu exposed a pop-up button, an unlabelled button and the arrow ("Go Down")
                // apart, and `accessibilityHidden` on the arrow didn't hold inside its label. So
                // VoiceOver gets one heading that folds, with the menu's items as its actions.
                .accessibilityRepresentation {
                    Button(action: toggle) { Text(verbatim: title) }
                }
                .accessibilityValue(Text(verbatim: spokenValue))
                .accessibilityAddTraits(.isHeader)
                .accessibilityActions { actions() }
            } else {
                // Other has no options, but its arrow showed the same way.
                foldButton
                    .accessibilityRepresentation {
                        Button(action: toggle) { Text(verbatim: title) }
                    }
                    .accessibilityValue(Text(verbatim: spokenValue))
                    .accessibilityAddTraits(.isHeader)
            }
        #endif
    }

    private var foldButton: some View {
        Button(action: toggle) { label }
            .buttonStyle(.clickable)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityValue(Text(verbatim: spokenValue))
            .accessibilityAddTraits(.isHeader)
    }

    /// "Folded, needs you, 3 unread": what the folded heading's indicator shows, and the rest.
    private var spokenValue: String {
        SidebarSpeech.section(block, isFolded: isFolded)
    }

    private var label: some View {
        HStack(spacing: 8) {
            Text(verbatim: title)
                .scaledFont(size: Self.titleSize, weight: Self.titleWeight)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1, accessibility: 3)
            #if os(iOS)
                // Grok's phone app: the arrow follows the name.
                chevron
            #endif
            Spacer(minLength: 0)
            if isFolded {
                ContactIndicator(needsYou: block.needsYou, unreadCount: block.unreadCount)
            }
            #if os(macOS)
                chevron
            #endif
        }
        #if os(macOS)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .hoverHighlight(in: RoundedRectangle(cornerRadius: 10))
        #else
            // The list's header insets place it.
            .frame(minHeight: 30)
        #endif
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .scaledFont(size: Self.chevronSize, weight: Self.chevronWeight)
            .foregroundStyle(Theme.secondaryInk.opacity(Self.chevronOpacity))
            .rotationEffect(.degrees(isFolded ? -90 : 0))
            .opacity(showsChevron ? 1 : 0)
            .accessibilityHidden(true)
    }

    private static var titleSize: CGFloat { SectionNameField.titleSize }
    private static var titleWeight: Font.Weight? { SectionNameField.titleWeight }

    #if os(macOS)
        private static var chevronSize: CGFloat { 10 }
        private static var chevronWeight: Font.Weight { .semibold }
        private static var chevronOpacity: Double { 1 }
    #else
        // Grok's phone headings: larger, with a thin, quieter arrow.
        private static var chevronSize: CGFloat { 13 }
        private static var chevronWeight: Font.Weight { .regular }
        private static var chevronOpacity: Double { 0.7 }
    #endif

    /// With no pointer to hover, iPhone always shows it. Folded, it's the sign there's more.
    private var showsChevron: Bool {
        #if os(macOS)
            isHovering || isFolded
        #else
            true
        #endif
    }
}

/// Types a section's name in place of its heading, in the heading's type and place. Esc on the
/// Mac or Cancel on iPhone keeps the old name, and so does leaving it empty; any other way of
/// leaving saves.
struct SectionNameField: View {
    let commit: (String) -> Void
    let cancel: () -> Void

    @State private var draft: String
    @State private var selection: TextSelection?
    @State private var isFinished = false
    @FocusState private var isFocused: Bool

    init(name: String, commit: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.commit = commit
        self.cancel = cancel
        _draft = State(initialValue: name)
    }

    var body: some View {
        HStack(spacing: 8) {
            field
            #if os(iOS)
                // iPhone has no Esc.
                Button("Cancel", action: dismiss)
                    .buttonStyle(.clickable(.borderless))
            #endif
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(Theme.selection, in: RoundedRectangle(cornerRadius: 10))
    }

    private var field: some View {
        TextField("Section name", text: $draft, selection: $selection)
            .textFieldStyle(.plain)
            .scaledFont(size: Self.titleSize, weight: Self.titleWeight)
            .foregroundStyle(Theme.ink)
            .focused($isFocused)
            #if os(iOS)
                .submitLabel(.done)
            #endif
            .onSubmit(finish)
            .onChange(of: isFocused) { _, focused in
                if !focused { finish() }
            }
            // On the Mac, clicking another chat leaves the focus here, and the list closes the field.
            .onDisappear(perform: finish)
            #if os(macOS)
                .onExitCommand(perform: dismiss)
            #endif
            .task {
                // The context menu that led here takes the focus back as it closes.
                try? await Task.sleep(for: .milliseconds(Self.menuCloseDelay))
                isFocused = true
                // A selection set before the field has focus is dropped.
                try? await Task.sleep(for: .milliseconds(50))
                selection = TextSelection(range: draft.startIndex..<draft.endIndex)
            }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        commit(draft)
    }

    private func dismiss() {
        guard !isFinished else { return }
        isFinished = true
        cancel()
    }

    #if os(macOS)
        static var titleSize: CGFloat { 12 }
        static var titleWeight: Font.Weight? { nil }
    #else
        static var titleSize: CGFloat { 17 }
        static var titleWeight: Font.Weight? { nil }
    #endif

    private static var menuCloseDelay: Int {
        #if os(macOS)
            100
        #else
            500
        #endif
    }
}

#if os(macOS)
    extension UTType {
        /// Declared in `Config/Info.plist`.
        fileprivate static let sidebarChat = UTType(exportedAs: "dev.usualbot.sidebar-chat")
    }

    /// A chat on its way to another section.
    struct SidebarDrag: Codable, Transferable {
        let id: Contact.ID

        static var transferRepresentation: some TransferRepresentation {
            CodableRepresentation(contentType: .sidebarChat)
        }
    }
#endif
