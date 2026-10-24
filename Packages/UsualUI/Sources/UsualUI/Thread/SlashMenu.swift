import HermesKit
import SwiftUI

/// What a message box needs for its `/` menu. Chats only: room agents take plain messages.
struct SlashCommands {
    let list: [SlashCommand]
    /// Reloads the list from the gateway, so a skill switched on a moment ago shows.
    let load: () -> Void
    /// Text a command put back (`/retry`); the box takes it and clears this.
    @Binding var prefill: String?

    /// The skills and commands matching what's typed after `/`: names starting with it first.
    func matching(_ query: String) -> [SlashCommand] {
        let query = query.lowercased()
        let named = list.filter { $0.name.dropFirst().lowercased().contains(query) || query.isEmpty }
        let starting = named.filter { $0.name.dropFirst().lowercased().hasPrefix(query) }
        return starting + named.filter { !starting.contains($0) }
    }
}

/// Something the message box's menu offers: a skill or command after `/`, or a room member after `@`.
enum Suggestion: Identifiable {
    case command(SlashCommand)
    case mention(Mention)

    var id: String {
        switch self {
        case .command(let command): command.name
        case .mention(let mention): "@" + mention.id
        }
    }
}

/// What matches what you're typing, above the message box. Up and Down move the highlight, Return
/// or Tab picks it, Escape closes the menu; on the Mac the pointer highlights too.
struct SuggestionMenu: View {
    let items: [Suggestion]
    let highlighted: Int
    let highlight: (Int) -> Void
    let pick: (Suggestion) -> Void

    /// Rows shown before the list scrolls.
    private static let visibleRows = 7
    private static let rowHeight: CGFloat = 36

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            pick(item)
                        } label: {
                            row(item)
                                .padding(.horizontal, 10)
                                .frame(minHeight: Self.rowHeight)
                                .background(
                                    index == highlighted ? Theme.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { highlight(index) } }
                        .accessibilityAddTraits(index == highlighted ? .isSelected : [])
                        .id(item.id)
                    }
                }
                .padding(4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: CGFloat(Self.visibleRows) * Self.rowHeight + 8)
            .fixedSize(horizontal: false, vertical: true)
            // Up and Down keep the highlighted row in view.
            .onChange(of: highlighted) { _, index in
                guard items.indices.contains(index) else { return }
                proxy.scrollTo(items[index].id)
            }
        }
        .floatingSurface(in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func row(_ item: Suggestion) -> some View {
        switch item {
        case .command(let command):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Skills and commands share the menu; the icon tells them apart.
                Image(systemName: command.kind == .skill ? "sparkles" : "command")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: 16)
                    .accessibilityLabel(Text(command.kind == .skill ? "Skill" : "Command"))
                Text(command.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    // The name stays whole; the description gives way.
                    .lineLimit(1)
                    .fixedSize()
                Text(command.description)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        case .mention(let mention):
            HStack(spacing: 8) {
                AgentAvatar(contact: mention.contact, size: 22)
                Text(mention.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("@\(mention.id)").font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Mention \(mention.name)"))
        }
    }
}
