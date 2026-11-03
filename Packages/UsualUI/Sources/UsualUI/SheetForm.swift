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

/// Every sheet's frame, so they all look and work alike. iPhone: a navigation bar with the title,
/// Cancel (or Back) leading and the main action trailing, out of the keyboard's way. Mac: the title
/// at the top; Back at the bottom left, Cancel and the main action at the bottom right, with Esc and
/// Return. `content` scrolls itself. `busy` names what's under way, such as "Creating…".
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
        #if os(macOS)
            VStack(spacing: 0) {
                title
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                Divider().overlay(Theme.border)
                content()
                    .frame(maxHeight: .infinity)
                Divider().overlay(Theme.border)
                footer
            }
            // A sheet sits outside the window's tint.
            .tint(Theme.ink)
        #else
            NavigationStack {
                content()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { leadingItem }
                        ToolbarItem(placement: .confirmationAction) { trailingItem }
                    }
            }
            .tint(Theme.ink)
            .interactiveDismissDisabled(busy != nil)
        #endif
    }

    #if os(macOS)
        private var footer: some View {
            HStack(spacing: 8) {
                if let back {
                    Button("Back", action: back.perform)
                        .buttonStyle(CardButtonStyle(primary: false))
                        .accessibilityLabel(back.label)
                        .disabled(busy != nil)
                }
                extra()
                if let busy {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 0)
                if let cancel {
                    Button("Cancel", role: .cancel, action: cancel)
                        .buttonStyle(CardButtonStyle(primary: false))
                        .keyboardShortcut(.cancelAction)
                        .disabled(busy != nil)
                } else if let action {
                    // Esc closes a sheet with no Cancel, as its action does.
                    Button("Close", action: action.perform)
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
                if let action {
                    let enabled = action.isEnabled && busy == nil
                    Group {
                        if action.role == .destructive {
                            Button(action.title, role: .destructive, action: action.perform)
                                .buttonStyle(DangerButtonStyle())
                        } else {
                            Button(action.title, role: action.role, action: action.perform)
                                .buttonStyle(CardButtonStyle(primary: true))
                        }
                    }
                    .keyboardShortcut(action.isDefault ? .defaultAction : nil)
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
        }
    #else
        @ViewBuilder private var leadingItem: some View {
            if let back {
                Button(action: back.perform) {
                    Label("Back", systemImage: "chevron.backward")
                }
                .accessibilityLabel(back.label)
                .disabled(busy != nil)
            } else if let cancel {
                Button("Cancel", role: .cancel, action: cancel)
                    .disabled(busy != nil)
            }
        }

        @ViewBuilder private var trailingItem: some View {
            if busy != nil {
                ProgressView()
            } else if let action {
                Button(action.title, role: action.role, action: action.perform)
                    .fontWeight(.semibold)
                    .disabled(!action.isEnabled)
                    .tint(action.role == .destructive ? Theme.danger : Theme.ink)
            }
        }
    #endif
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

#if os(macOS)
    /// Red, so a destructive action can't pass for the usual primary button.
    struct DangerButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                // Deeper than `Theme.danger` in dark mode, which white text doesn't read on.
                .background(Color(light: 0xB42318, dark: 0xD92D20), in: Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Capsule())
                .clickable()
        }
    }
#endif
