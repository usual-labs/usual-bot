import HermesKit
import SwiftUI

/// The messages waiting above the message box, in the order they'll go: held ones first (Stop took
/// them back, and they wait for Resume), then the ones the gateway sends when the reply ends. Each
/// can be edited (back into the box), sent now or removed.
struct QueuedMessages: View {
    let thread: ChatThread
    /// About four one-line rows before the list scrolls. It grows with the text, short of taking
    /// the chat's place.
    @ScaledMetric(relativeTo: .body) private var listHeight: CGFloat = 136

    var body: some View {
        let held = thread.queue.filter(\.isHeld)
        let waiting = thread.queue.filter { !$0.isHeld }
        VStack(alignment: .leading, spacing: 6) {
            if !held.isEmpty {
                HStack(spacing: 8) {
                    heading("Held. These aren't sent until you resume.")
                    Spacer(minLength: 0)
                    Button("Resume") { thread.resumeQueue() }
                        .buttonStyle(.clickable(.borderless))
                        .scaledFont(size: 12, weight: .semibold)
                        .disabled(!thread.canSend)
                        .accessibilityLabel(Text("Resume the held messages"))
                        .accessibilityHint(Text("Sends them one after another, in this order"))
                        .padding(.trailing, 8)
                }
                rows(held)
            }
            if !waiting.isEmpty {
                heading(
                    thread.isAttached
                        ? "Queued. Each is sent when the reply before it ends."
                        : "Queued on your gateway, which sends each when the reply before it ends.")
                rows(waiting)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Queued messages"))
    }

    private func heading(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .scaledFont(size: 12, weight: .semibold)
            .foregroundStyle(Theme.secondaryInk)
            // Wraps at large text sizes, where one line would cut the sentence short.
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// Past four they scroll, as quotes do, so a long queue doesn't push the chat off an iPhone.
    private func rows(_ messages: [QueuedMessage]) -> some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(messages) { message in
                    QueuedMessageRow(message: message, thread: thread)
                }
            }
        }
        .thinScroller()
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: min(listHeight, 260))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct QueuedMessageRow: View {
    let message: QueuedMessage
    let thread: ChatThread

    var body: some View {
        // A held message stays yours offline; one on the gateway needs the gateway.
        let ready = !message.isSending && (message.isHeld || thread.canSend)
        HStack(spacing: 2) {
            Text(message.text)
                .scaledFont(size: 13)
                .foregroundStyle(message.isSending ? Theme.secondaryInk : Theme.ink)
                .lineLimit(2, accessibility: 4)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(
                    Text(message.isHeld ? "Held message: \(message.text)" : "Queued message: \(message.text)"))
            button("pencil", "Edit", hint: "Takes it out of the queue and puts it in the message box") {
                thread.edit(message)
            }
            .disabled(!ready)
            button(
                "arrow.up", "Send Now",
                hint: thread.state.isRunning ? "Steers the reply that's running" : "Sends it as your next message"
            ) { thread.sendNow(message) }
            .disabled(!ready || !thread.canSend)
            button("xmark", "Remove", hint: "Takes it out of the queue") { thread.remove(message) }
                .disabled(!ready)
        }
    }

    private func button(
        _ systemImage: String, _ label: LocalizedStringKey, hint: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .touchTarget(width: 26, height: 26)
        }
        .buttonStyle(.clickable(.borderless))
        .foregroundStyle(.secondary)
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(hint))
    }
}
