import SwiftUI

/// A round button in the chat's bar for something of the agent's you can watch live: its computer,
/// its browser, its terminal. A dot shows while the agent is using it.
struct LiveButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let working: Bool
    /// What it opens is showing (the terminal drawer): the button is ringed.
    var isOn = false
    let action: () -> Void

    init(
        _ title: LocalizedStringKey, systemImage: String, working: Bool, isOn: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.working = working
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                #if os(macOS)
                    // The name capsule's glass, level with it and as tall: the system's glass
                    // button drew a pale disc in the window you're at, unlike the capsule beside it.
                    .zoomedFont(size: 15, weight: .medium)
                    .foregroundStyle(Theme.ink)
                    .zoomedFrame(width: ThreadPane.barItemHeight, height: ThreadPane.barItemHeight)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
                    .overlay {
                        if isOn { Circle().strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1.5) }
                    }
                #endif
                .overlay(alignment: .topTrailing) {
                    if working {
                        Circle().fill(Theme.online).zoomedFrame(width: 9, height: 9)
                            #if os(macOS)
                                .offset(x: -1, y: 1)
                            #else
                                .offset(x: 3, y: -3)
                            #endif
                            .accessibilityHidden(true)
                    }
                }
        }
        #if os(macOS)
            .buttonStyle(.clickable)
        #endif
        .accessibilityValue(working ? Text("In use") : Text(""))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
