#if os(iOS)
    import SwiftUI

    /// One action in a message's menu.
    struct MessageMenuItem {
        let title: Text
        let systemImage: String
        var isDestructive = false
        var isDisabled = false
        let action: () -> Void
    }

    /// iPhone's touch-and-hold menu for a message, as in Grok's app: a sheet from the bottom with
    /// reactions in a grid and the actions in groups under them. A context menu lifted the whole
    /// message over the screen, and a long reply pushed the menu half off it.
    struct MessageMenuSheet: View {
        /// `nil` where the message can't be reacted to: rooms, and anything but words.
        let react: ((String) -> Void)?
        let groups: [[MessageMenuItem]]
        /// Why the greyed-out actions can't run now.
        let note: String?
        let date: Date?
        /// Closes the sheet, then runs the action, so one that opens a sheet or the keyboard can.
        let run: (@escaping () -> Void) -> Void

        @State private var showsAllReactions = false
        @State private var height: CGFloat = 420
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private static let columns = 6
        private static let circle: CGFloat = 48

        var body: some View {
            ScrollView {
                VStack(spacing: 14) {
                    if let react { reactions(react) }
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        if !group.isEmpty { section(group) }
                    }
                    if let note {
                        Text(note)
                            .scaledFont(size: 13)
                            .foregroundStyle(Theme.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    if let date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .scaledFont(size: 13)
                            .foregroundStyle(Theme.secondaryInk)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .presentationDetents([.height(height), .large])
            .presentationDragIndicator(.visible)
        }

        // MARK: Reactions

        private func reactions(_ react: @escaping (String) -> Void) -> some View {
            let all = quickReactions + moreReactions
            // Two rows, as Grok shows: eleven faces and a twelfth circle for the rest.
            let shown = showsAllReactions ? all : Array(all.prefix(Self.columns * 2 - 1))
            return LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.columns), spacing: 12
            ) {
                ForEach(shown, id: \.self) { emoji in
                    Button {
                        run { react(emoji) }
                    } label: {
                        Text(emoji).scaledFont(size: 24).modifier(Circled(size: Self.circle))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("React \(emoji)"))
                }
                if !showsAllReactions {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) { showsAllReactions = true }
                    } label: {
                        Image(systemName: "plus")
                            .scaledFont(size: 20, weight: .semibold)
                            .foregroundStyle(Theme.secondaryInk)
                            .modifier(Circled(size: Self.circle))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("More Reactions"))
                }
            }
        }

        private struct Circled: ViewModifier {
            let size: CGFloat

            func body(content: Content) -> some View {
                content
                    .frame(width: size, height: size)
                    .background(.fill.tertiary, in: Circle())
                    .contentShape(Circle())
            }
        }

        // MARK: Actions

        private func section(_ items: [MessageMenuItem]) -> some View {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider().padding(.leading, 52) }
                    row(item)
                }
            }
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }

        private func row(_ item: MessageMenuItem) -> some View {
            Button {
                run(item.action)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: item.systemImage)
                        .scaledFont(size: 17, weight: .medium)
                        .frame(width: 24)
                    item.title.scaledFont(size: 17)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(item.isDestructive ? Theme.danger : Theme.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.isDisabled)
            .opacity(item.isDisabled ? 0.4 : 1)
        }
    }
#endif
