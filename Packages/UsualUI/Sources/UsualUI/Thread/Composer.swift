import HermesKit
import SwiftUI

/// The message box under a chat with one agent. The chat's model, thinking and context are in the
/// agent's profile (ChatModelSection), on iPhone and Mac alike. Return
/// sends. While the agent works, a message steers it, or waits in the queue above the box for the
/// reply to end, and the empty box's button stops it. Files go with a message between turns, or wait
/// with it in the queue.
struct Composer: View {
    let thread: ChatThread
    /// Whose chat this is, for its draft.
    let chatID: Contact.ID
    let agentName: String
    @Binding var attachments: [Attachment]
    @Binding var quotes: [QuotedMessage]
    /// The message of yours you're rewriting: Send replaces it, and removes what came after it.
    @Binding var editing: TranscriptItem.ID?
    /// Asks before an edit that removes more than the last exchange, or what the Bot acted in.
    var confirm: (RewindRequest) -> Void = { _ in }
    /// A call holds the microphone: no dictation or second call meanwhile.
    var inCall = false
    var startCall: (() -> Void)?
    @Environment(\.drafts) private var drafts
    /// The text while you rewrite a message. Your draft waits meanwhile, and is back in
    /// the box once the edit is sent or stopped.
    @State private var edit = ""

    var body: some View {
        // Background tasks and side answers float above the box.
        VStack(alignment: .trailing, spacing: 0) {
            if let warning = thread.planLimitWarning {
                PlanLimitNotice(warning: warning, text: warning.chatText(agentName: agentName)).padding(.bottom, 6)
            }
            if let goal = thread.goal, let phase = thread.goalPhase {
                // Opened in one chat, it stays closed in the next.
                GoalBar(thread: thread, goal: goal, phase: phase, agentName: agentName).id(chatID).padding(.bottom, 6)
            }
            if !thread.backgroundTasks.isEmpty {
                BackgroundTasksBar(tasks: thread.backgroundTasks).padding(.bottom, 6)
            }
            ForEach(thread.sideQuestions) { question in
                SideQuestionCard(question: question) { thread.dismiss(question) }
                    .padding(.bottom, 6)
            }
            if !thread.queue.isEmpty {
                QueuedMessages(thread: thread).padding(.bottom, 6)
            }
            box
        }
        // The box stays as you switch chats, so each chat's models are asked for when it opens.
        .task(id: "\(chatID) \(thread.isAttached)") { await thread.loadModelsAndUsage() }
        // A reply uses up some of the subscription: read its limits again once it ends. Going to a
        // chat that isn't replying isn't one ending.
        .onChange(of: Running(chat: chatID, isRunning: thread.state.isRunning)) { old, new in
            if old.chat == new.chat, !new.isRunning { Task { await thread.refreshPlanLimits() } }
        }
        .onChange(of: editing) { if editing == nil { edit = "" } }
        // A queued message you edit puts its files back beside its text.
        .onChange(of: thread.returnedAttachments, initial: true) { _, returned in
            guard !returned.isEmpty else { return }
            attachments += returned
            thread.returnedAttachments = []
        }
        // Item IDs start over with each copy of the chat, so an edit can't outlast one.
        .onChange(of: thread.transcriptLoad) { editing = nil }
        .onChange(of: edited == nil) { _, gone in if gone { editing = nil } }
        // Another chat's queue and cards replace these at once rather than slide in.
        .transaction(value: chatID) { $0.animation = nil }
        .animation(.smooth(duration: 0.2), value: thread.sideQuestions)
        .animation(.smooth(duration: 0.2), value: thread.backgroundTasks)
        .animation(.smooth(duration: 0.2), value: thread.queue)
        .animation(.smooth(duration: 0.2), value: thread.goal == nil)
        .animation(.smooth(duration: 0.2), value: thread.planLimitWarning)
    }

    private var box: some View {
        MessageBox(
            conversation: chatID,
            text: Binding(
                get: { editing != nil ? edit : drafts?[chatID] ?? "" },
                set: { if editing != nil { edit = $0 } else { drafts?[chatID] = $0 } }),
            placeholder: placeholder, isRunning: thread.state.isRunning, canSend: thread.canSend,
            stopLabel: stopLabel,
            attaching: AttachmentSending(
                attachments: $attachments, canSend: thread.takesAttachments, isUploading: thread.isUploading,
                send: { await thread.send($0, attachments: $1) }),
            quotes: $quotes, editing: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
            // The reason an earlier message can't be replaced yet, in place of what would go.
            editingLabel: edited.map {
                (isLast($0) ? nil : thread.rewindUnavailable)
                    ?? RewindRequest.editingLabel(for: thread.rewindCost(of: $0))
            },
            startCall: thread.isAttached ? startCall : nil, inCall: inCall,
            transcriptionProfile: thread.contactID,
            commands: SlashCommands(
                list: thread.commands, load: { Task { await thread.loadCommands() } },
                prefill: Binding(get: { thread.prefill }, set: { thread.prefill = $0 })),
            opensForTyping: true,
            queue: queue, send: send, stop: thread.stop)
    }

    /// An edit replaces the message and what follows it; it isn't one to queue.
    private struct Running: Equatable {
        let chat: Contact.ID
        let isRunning: Bool
    }

    private var queue: ((String) -> Void)? {
        guard thread.canQueue, editing == nil else { return nil }
        return { thread.enqueue($0) }
    }

    private var edited: TranscriptItem? {
        editing.flatMap { id in thread.state.items.first { $0.id == id } }
    }

    private func isLast(_ item: TranscriptItem) -> Bool { item.id == thread.lastSent?.id }

    private func send(_ text: String) {
        guard let item = edited else {
            editing = nil
            return thread.send(text)
        }
        guard thread.canRewind, let cost = thread.rewindCost(of: item) else {
            if isLast(item) {
                // A reply that started meanwhile can't be undone under it; the text goes as a new message.
                editing = nil
                thread.send(text)
            } else {
                // Steering the reply with words meant for an earlier point would make no sense: the
                // edit waits, and the box says for what.
                edit = text
            }
            return
        }
        if cost.needsConfirmation {
            // The box emptied as it sent; the text stays until you've said yes.
            edit = text
            confirm(RewindRequest(kind: .edit(item, text: text), cost: cost))
            return
        }
        editing = nil
        Task { await thread.edit(item, to: text) }
    }

    /// With a goal at work, the box's Stop ends only the reply: the goal bar's Stop Goal ends the goal.
    private var stopLabel: String {
        thread.goalPhase == .working
            ? String(localized: "Stop this reply. The goal carries on.") : String(localized: "Stop \(agentName)")
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
