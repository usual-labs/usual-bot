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
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityValue(isFolded ? Text("Folded") : Text("Open"))
                .accessibilityHint(Text("Touch and hold for the section's options"))
                .accessibilityAddTraits(.isHeader)
            } else {
                foldButton
            }
        #endif
    }

    private var foldButton: some View {
        Button(action: toggle) { label }
            .buttonStyle(.clickable)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityValue(isFolded ? Text("Folded") : Text("Open"))
            .accessibilityAddTraits(.isHeader)
    }

    private var label: some View {
        HStack(spacing: 8) {
            Text(verbatim: title)
                .font(Self.titleFont)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1)
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
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .hoverHighlight(in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: Self.chevronSize, weight: .semibold))
            .foregroundStyle(Theme.secondaryInk)
            .rotationEffect(.degrees(isFolded ? -90 : 0))
            .opacity(showsChevron ? 1 : 0)
            .accessibilityHidden(true)
    }

    #if os(macOS)
        private static var titleFont: Font { .system(size: 13, weight: .medium) }
        private static var chevronSize: CGFloat { 10 }
    #else
        private static var titleFont: Font { .system(size: 16) }
        private static var chevronSize: CGFloat { 12 }
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

/// Types a section's name in place of its heading. Esc cancels; any other way of leaving saves.
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
        TextField("Section name", text: $draft, selection: $selection)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.ink)
            .focused($isFocused)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(Theme.selection, in: RoundedRectangle(cornerRadius: 10))
            .onSubmit(finish)
            .onChange(of: isFocused) { _, focused in
                if !focused { finish() }
            }
            // On the Mac, clicking another chat leaves the focus here, and the list closes the field.
            .onDisappear(perform: finish)
            #if os(macOS)
                .onExitCommand {
                    isFinished = true
                    cancel()
                }
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
