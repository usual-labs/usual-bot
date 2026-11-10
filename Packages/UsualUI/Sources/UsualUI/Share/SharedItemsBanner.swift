import HermesKit
import SwiftUI

/// What you shared from other apps and Usual Bot hasn't sent yet, below the chat list: waiting
/// for the connection or for a Bot to finish, or failed, with why and what to do. It goes once
/// everything is in its chat.
struct SharedItemsBanner: View {
    let outbox: SharedOutbox
    /// Why nothing sends right now, when the app is offline.
    var offline = false

    var body: some View {
        if !outbox.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(outbox.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title(item))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.ink)
                        Text(detail(item))
                            .foregroundStyle(item.failure == nil ? Theme.secondaryInk : Theme.needsYouInk)
                        HStack(spacing: 8) {
                            if item.failure != nil {
                                Button("Try Again") { outbox.retry(item) }
                                    .buttonStyle(.clickable(.borderedProminent))
                            }
                            Button(item.failure == nil ? "Don't Send" : "Delete") { outbox.discard(item) }
                                .buttonStyle(.clickable(.bordered))
                        }
                        .controlSize(.small)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .scaledFont(size: 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Shared items"))
        }
    }

    private func title(_ item: SharedItem) -> String {
        item.failure == nil
            ? String(localized: "Waiting to send to \(item.contactName)")
            : String(localized: "Didn't send to \(item.contactName)")
    }

    private func detail(_ item: SharedItem) -> String {
        if let failure = item.failure { return "\(item.title): \(failure)" }
        return offline
            ? String(localized: "\(item.title). It sends when Usual Bot reconnects.")
            : String(localized: "\(item.title). It sends when the chat is free.")
    }
}

extension AppModel.Link {
    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }
}
