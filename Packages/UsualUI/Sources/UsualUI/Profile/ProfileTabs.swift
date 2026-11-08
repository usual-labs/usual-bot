#if os(macOS)
    import SwiftUI

    /// The profile panel's pages as a capsule of glass, like the chat's header buttons, with a grey
    /// pill under the open page. The developer's choice (November 2026) over the system's segmented
    /// control, whose selected segment is white in dark mode and whose regular size doesn't fit
    /// the panel. Each page is a button: Tab and Space move and pick, and VoiceOver hears which is
    /// selected.
    struct ProfileTabs: View {
        @Binding var selection: ProfilePanel.Tab

        var body: some View {
            HStack(spacing: 0) {
                ForEach(ProfilePanel.Tab.allCases, id: \.self) { tab in
                    let selected = tab == selection
                    // No animation: each page is its own form with these tabs at its top, so an
                    // animated switch cross-faded the whole panel, header and all. Unanimated, the
                    // top draws the same and only the page beneath it changes.
                    Button {
                        selection = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Theme.ink : Theme.secondaryInk)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.height - Self.inset * 2)
                            .background {
                                if selected {
                                    Capsule().fill(Theme.ink.opacity(0.1))
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.clickable)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(Self.inset)
            .glassEffect(.regular, in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Page"))
        }

        /// As tall as the header's buttons.
        private static let height = ThreadPane.barItemHeight
        private static let inset: CGFloat = 4
    }
#endif
