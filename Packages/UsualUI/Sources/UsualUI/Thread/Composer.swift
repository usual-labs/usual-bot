import HermesKit
import SwiftUI

/// The message box under a chat with one agent. On iPhone its model, thinking and context sit
/// inside it while you type; on the Mac they're in the agent's panel (ChatModelSection). Return
/// sends. While the agent works, a message steers it and the empty box's button stops it. Files can
/// go with a message between turns.
struct Composer: View {
    let thread: ChatThread
    /// Whose chat this is, for its draft.
    let chatID: Contact.ID
    let agentName: String
    /// The agent's default model, for the model menu's Make Default.
    var agentDefault: AgentDetails?
    @Binding var attachments: [Attachment]
    @Binding var quotes: [QuotedMessage]
    /// You're rewriting your last message: Send replaces it.
    @Binding var editing: Bool
    /// A call holds the microphone: no dictation or second call meanwhile.
    var inCall = false
    var startCall: (() -> Void)?
    @Environment(\.drafts) private var drafts
    /// The text while you rewrite your last message. Your draft waits meanwhile, and is back in
    /// the box once the edit is sent or stopped.
    @State private var edit = ""

    var body: some View {
        // Background tasks and side answers float above the box.
        VStack(alignment: .trailing, spacing: 0) {
            if !thread.backgroundTasks.isEmpty {
                BackgroundTasksBar(tasks: thread.backgroundTasks).padding(.bottom, 6)
            }
            ForEach(thread.sideQuestions) { question in
                SideQuestionCard(question: question) { thread.dismiss(question) }
                    .padding(.bottom, 6)
            }
            box
        }
        .task(id: thread.isAttached) { await thread.loadModelsAndUsage() }
        .onChange(of: editing) { if !editing { edit = "" } }
        .animation(.smooth(duration: 0.2), value: thread.sideQuestions)
        .animation(.smooth(duration: 0.2), value: thread.backgroundTasks)
    }

    private var box: some View {
        MessageBox(
            conversation: chatID,
            text: Binding(
                get: { editing ? edit : drafts?[chatID] ?? "" },
                set: { if editing { edit = $0 } else { drafts?[chatID] = $0 } }),
            placeholder: placeholder, isRunning: thread.state.isRunning, canSend: thread.canSend,
            stopLabel: String(localized: "Stop \(agentName)"),
            attaching: AttachmentSending(
                attachments: $attachments, canSend: thread.canSendAttachments, isUploading: thread.isUploading,
                send: thread.send(_:attachments:)),
            quotes: $quotes, editing: $editing, startCall: thread.isAttached ? startCall : nil, inCall: inCall,
            commands: SlashCommands(
                list: thread.commands, load: { Task { await thread.loadCommands() } },
                prefill: Binding(get: { thread.prefill }, set: { thread.prefill = $0 })),
            chat: ChatControls(thread: thread, agentName: agentName, agentDefault: agentDefault),
            send: send, stop: thread.stop)
    }

    private func send(_ text: String) {
        guard editing else { return thread.send(text) }
        editing = false
        // A reply that started meanwhile can't be undone under it; the text goes as a new message.
        if thread.canRewind { Task { await thread.edit(text) } } else { thread.send(text) }
    }

    private var placeholder: String {
        if !thread.isAttached { return String(localized: "Reconnecting…") }
        if thread.questionTheBoxAnswers != nil { return String(localized: "Answer \(agentName)") }
        if thread.state.isRunning { return String(localized: "Steer \(agentName) while it works") }
        return String(localized: "Ask \(agentName)")
    }
}

/// Someone you can @mention in a room.
struct Mention: Identifiable, Equatable {
    /// The handle the gateway routes by.
    let id: String
    let name: String
    let contact: Contact
}

extension EnvironmentValues {
    /// Where message boxes keep what's typed and not sent; without it nothing is kept.
    @Entry var drafts: Drafts?
}
