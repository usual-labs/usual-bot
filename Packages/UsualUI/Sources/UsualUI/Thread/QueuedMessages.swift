import HermesKit
import SwiftUI

/// The messages waiting above the message box, in the order they'll go: held ones first (Stop took
/// them back, and they wait for Resume), then the ones the gateway sends when the reply ends. Each
/// can be edited (back into the box, files too), sent now or removed. Files can't steer a reply,
/// so a message with files is sent now only when nothing runs.
struct QueuedMessages: View {
    let thread: ChatThread
    /// About four one-line rows before the list scrolls. It grows with the text, short of taking
    /// the chat's place.
    @ScaledSize(relativeTo: .body) private var listHeight: CGFloat = 136

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
            if message.isFromWidget {
                // What a widget asks is for the agent, as when it's sent at once: only taking it
                // back is yours.
                Text("From a widget")
                    .scaledFont(size: 13)
                    .italic()
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Text("Queued from a widget"))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .scaledFont(size: 13)
                            .foregroundStyle(message.isSending ? Theme.secondaryInk : Theme.ink)
                            .lineLimit(2, accessibility: 4)
                            .truncationMode(.tail)
                    }
                    if !files.isEmpty {
                        Label(files, systemImage: "paperclip")
                            .scaledFont(size: 12)
                            .foregroundStyle(Theme.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                button(
                    "pencil", "Edit",
                    hint: message.canEdit
                        ? "Takes it out of the queue and puts it in the message box"
                        : "Unavailable: its files were picked before the app last opened"
                ) { thread.edit(message) }
                .disabled(!ready || !message.canEdit)
                button(
                    "arrow.up", "Send Now",
                    hint: !thread.state.isRunning
                        ? "Sends it as your next message"
                        : message.files.isEmpty
                            ? "Steers the reply that's running" : "Unavailable: a running reply can't take files"
                ) { thread.sendNow(message) }
                .disabled(!ready || !thread.canSendNow(message))
            }
            button("xmark", "Remove", hint: "Takes it out of the queue") { thread.remove(message) }
                .disabled(!ready)
        }
    }

    private var files: String { message.files.map(\.name).formatted(.list(type: .and)) }

    private var accessibilityLabel: Text {
        let text =
            message.text.isEmpty ? files : message.files.isEmpty ? message.text : "\(message.text), with \(files)"
        return message.isHeld ? Text("Held message: \(text)") : Text("Queued message: \(text)")
    }

    private func button(
        _ systemImage: String, _ label: LocalizedStringKey, hint: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .zoomedFont(size: 11, weight: .semibold)
                .zoomedFrame(width: 26, height: 26)
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
