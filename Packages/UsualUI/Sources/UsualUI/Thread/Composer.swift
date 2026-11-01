import HermesKit
import SwiftUI

/// The message box under a chat with one agent, with its model and thinking choices (menus under
/// the box on the Mac, controls inside it while you type on iPhone). Return sends. While the agent
/// works, a message steers it and the empty box's button stops it. Files can go with a message
/// between turns.
struct Composer: View {
    let thread: ChatThread
    let agentName: String
    /// The agent's default model, for the model menu's Make Default.
    var agentDefault: AgentDetails?
    @Binding var attachments: [Attachment]
    @Binding var replyTo: QuotedMessage?
    /// You're rewriting your last message: Send replaces it.
    @Binding var editing: Bool
    /// A call holds the microphone: no dictation or second call meanwhile.
    var inCall = false
    var startCall: (() -> Void)?

    var body: some View {
        // Background tasks and side answers float above the box; on the Mac the model and thinking
        // menus sit under it, on the right.
        VStack(alignment: .trailing, spacing: ModelControls.gap) {
            if !thread.backgroundTasks.isEmpty {
                BackgroundTasksBar(tasks: thread.backgroundTasks).padding(.bottom, 6)
            }
            ForEach(thread.sideQuestions) { question in
                SideQuestionCard(question: question) { thread.dismiss(question) }
                    .padding(.bottom, 6)
            }
            box
            #if os(macOS)
                ModelControls(thread: thread, agentName: agentName, agentDefault: agentDefault)
            #endif
        }
        #if os(iOS)
            .task(id: thread.isAttached) { await thread.loadModelsAndUsage() }
        #endif
        .animation(.smooth(duration: 0.2), value: thread.sideQuestions)
        .animation(.smooth(duration: 0.2), value: thread.backgroundTasks)
    }

    private var box: some View {
        MessageBox(
            placeholder: placeholder, isRunning: thread.state.isRunning, canSend: thread.canSend,
            stopLabel: String(localized: "Stop \(agentName)"),
            attaching: AttachmentSending(
                attachments: $attachments, canSend: thread.canSendAttachments, isUploading: thread.isUploading,
                send: thread.send(_:attachments:)),
            replyTo: $replyTo, editing: $editing, startCall: thread.isAttached ? startCall : nil, inCall: inCall,
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
        if thread.state.isRunning { return String(localized: "Steer \(agentName) while it works") }
        return String(localized: "Message \(agentName)")
    }
}

/// Someone you can @mention in a room.
struct Mention: Identifiable, Equatable {
    /// The handle the gateway routes by.
    let id: String
    let name: String
    let contact: Contact
}
