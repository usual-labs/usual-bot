import SwiftUI

/// A sheet's main button: Create, Add, Save, Done or Delete.
struct SheetAction {
    let title: LocalizedStringKey
    var role: ButtonRole? = nil
    /// Off until the form is filled in.
    var isEnabled = true
    /// Return presses it on the Mac. Off where pressing it by accident would lose something.
    var isDefault = true
    let perform: () -> Void
}

/// A way back to the sheet's previous page, such as the routine templates.
struct SheetBack {
    /// What VoiceOver says for Back, naming where it goes.
    let label: Text
    let perform: () -> Void
}

/// Every sheet's frame, from the system's own parts: `content` is a `Form`, grouped here, which
/// scrolls itself, and the buttons are toolbar items in the cancellation and confirmation slots.
/// iPhone draws them in its glass bar, the confirmation prominent; the Mac puts them at the
/// bottom right, with Esc and Return. A destructive action's role colours it red. `busy` names
/// what's under way, such as "Creating…".
struct SheetForm<Content: View, Extra: View>: View {
    let title: Text
    var back: SheetBack? = nil
    /// `nil` leaves Cancel out, for a sheet whose action only closes it (Done).
    var cancel: (() -> Void)? = nil
    var action: SheetAction? = nil
    var busy: LocalizedStringKey? = nil
    /// Mac only, at the bottom left: a secondary action such as Remove. On iPhone the content holds it.
    @ViewBuilder var extra: () -> Extra
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .formStyle(.grouped)
                .navigationTitle(title)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { bar }
        }
        // A sheet sits outside the window's tint.
        .tint(Theme.ink)
        .interactiveDismissDisabled(busy != nil)
    }

    @ToolbarContentBuilder private var bar: some ToolbarContent {
        #if os(iOS)
            // One leading slot: Back where there's somewhere to go back to, else Cancel. A swipe
            // down still closes the sheet.
            ToolbarItem(placement: .cancellationAction) {
                if let back {
                    backButton(back)
                } else if let cancel {
                    cancelButton(cancel)
                }
            }
        #else
            // Back at the top left, as a window's; Cancel stays beside the action.
            if let back {
                ToolbarItem(placement: .navigation) { backButton(back) }
            }
            ToolbarItem(placement: .cancellationAction) {
                if let cancel {
                    cancelButton(cancel)
                } else if back == nil, let action {
                    // Esc closes a sheet with no Cancel, as its action does.
                    Button("Close", action: action.perform)
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        #endif
        #if os(macOS)
            if hasExtra {
                ToolbarItem(placement: .destructiveAction) { extra() }
            }
            if let busy {
                ToolbarItem(placement: .status) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(busy).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        #endif
        if let action {
            ToolbarItem(placement: placement(action)) {
                #if os(iOS)
                    if busy != nil {
                        ProgressView()
                    } else {
                        mainButton(action)
                    }
                #else
                    mainButton(action)
                #endif
            }
        }
    }

    /// The Mac may make a confirmation item the default button, so an action Return mustn't press
    /// (Delete Bot) takes the destructive slot there.
    private func placement(_ action: SheetAction) -> ToolbarItemPlacement {
        #if os(macOS)
            action.isDefault ? .confirmationAction : .destructiveAction
        #else
            .confirmationAction
        #endif
    }

    private func backButton(_ back: SheetBack) -> some View {
        Button("Back", systemImage: "chevron.backward", action: back.perform)
            .accessibilityLabel(back.label)
            // Esc goes back where there's no Cancel to take it.
            .keyboardShortcut(cancel == nil ? .cancelAction : nil)
            .disabled(busy != nil)
    }

    /// iPhone's is the system's ✕; the Mac's says Cancel.
    private func cancelButton(_ cancel: @escaping () -> Void) -> some View {
        #if os(iOS)
            Button(role: .cancel, action: cancel)
                .disabled(busy != nil)
        #else
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
                .disabled(busy != nil)
        #endif
    }

    /// Keeps its word (Create, Add, Delete Bot): a checkmark wouldn't say which. On iPhone the bar
    /// draws it as a plain glass button, so it's made prominent here; a destructive one stays
    /// plain, its role colouring it red.
    @ViewBuilder private func mainButton(_ action: SheetAction) -> some View {
        let button = Button(action.title, role: action.role, action: action.perform)
            .keyboardShortcut(action.isDefault ? .defaultAction : nil)
            .disabled(!action.isEnabled || busy != nil)
        #if os(iOS)
            if action.role == .destructive {
                button
            } else {
                // Glass picks a label that reads on the ink, unlike `.borderedProminent`.
                button.buttonStyle(.glassProminent)
            }
        #else
            button.tint(Theme.prominent)
        #endif
    }

    private var hasExtra: Bool { Extra.self != EmptyView.self }
}

extension SheetForm where Extra == EmptyView {
    init(
        title: Text, back: SheetBack? = nil, cancel: (() -> Void)? = nil, action: SheetAction? = nil,
        busy: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title, back: back, cancel: cancel, action: action, busy: busy, extra: { EmptyView() },
            content: content)
    }
}
