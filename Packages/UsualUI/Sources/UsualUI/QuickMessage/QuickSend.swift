import HermesKit
import SwiftUI

/// Whether a quick message can go now, should wait for its chat to open, or can't go, and why.
enum QuickSend: Equatable {
    case ready
    /// The chat is still opening, or the app is still connecting: send once it's open.
    case opening
    case blocked(String)

    static func readiness(
        canSend: Bool, link: AppModel.Link, failure: String?, roomServiceStopped: Bool = false
    ) -> QuickSend {
        if canSend { return .ready }
        if case .offline = link {
            return .blocked(
                String(localized: "You're offline, so this didn't send. Send it again once Usual Bot reconnects."))
        }
        if let failure { return .blocked(failure) }
        if roomServiceStopped {
            return .blocked(String(localized: "The gateway's room service isn't running, so agents won't answer."))
        }
        return .opening
    }
}

/// Under the message box: a message waiting for its chat to open, or why the last one didn't go.
struct QuickSendStatus: View {
    let waitingFor: String?
    let problem: String?
    let cancel: () -> Void

    var body: some View {
        if let waitingFor {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Opening the chat with \(waitingFor). Your message sends when it's ready.")
                Spacer(minLength: 8)
                Button("Cancel", action: cancel)
                    .buttonStyle(.clickable)
                    .foregroundStyle(Theme.ink)
            }
            .modifier(StatusLine())
        } else if let problem {
            Text(problem)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(StatusLine())
        }
    }

    private struct StatusLine: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryInk)
                .padding(.horizontal, 26)
                .padding(.bottom, 12)
        }
    }
}

extension ChatThread.Phase {
    var failure: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }
}

extension RoomThread.Phase {
    var failure: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }
}
