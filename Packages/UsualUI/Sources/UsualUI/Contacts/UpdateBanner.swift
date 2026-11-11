import HermesKit
import SwiftUI

/// A newer build is in TestFlight: below the chat list, until you update or say Later. Settings ›
/// About keeps offering it after Later.
struct UpdateBanner: View {
    let update: AppUpdate
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let build = update.available {
            VStack(alignment: .leading, spacing: 8) {
                Text(title(build))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    Button("Update in TestFlight") { openURL(build.testFlight) }
                        .buttonStyle(.inkProminent)
                    Button("Later", action: update.putOff)
                        .buttonStyle(.clickable(.bordered))
                }
                .controlSize(.small)
            }
            .scaledFont(size: 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
        }
    }

    private func title(_ build: AppUpdate.Build) -> String {
        if build.version.isEmpty { return String(localized: "A new Usual Bot is out.") }
        if build.isSameVersion { return String(localized: "A newer build of Usual Bot \(build.version) is out.") }
        return String(localized: "Usual Bot \(build.version) is out.")
    }
}
