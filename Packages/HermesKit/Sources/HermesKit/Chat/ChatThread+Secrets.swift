import Foundation

extension ChatThread {
    /// What you type into a prompt can be read on the network on its way to this gateway.
    public var isLinkUnencrypted: Bool { gateway?()?.isUnencrypted ?? false }

    func receive(_ prompt: SecretPrompt) {
        guard !secrets.contains(where: { $0.id == prompt.id }) else { return }
        secrets.append(prompt)
    }

    /// Sends the value to the gateway. It goes nowhere else: notices name what was asked for, never
    /// the answer. An empty value means "skipped" to the gateway, so that's `skip(_:)`'s job.
    public func answer(_ prompt: SecretPrompt, with value: String) {
        guard !value.isEmpty, let index = secrets.firstIndex(where: { $0.id == prompt.id }), let channel = channel()
        else { return }
        secrets.remove(at: index)
        switch prompt.kind {
        case .secret(let name, _): state.addNotice(String(localized: "You sent \(name)"))
        case .sudo: state.addNotice(String(localized: "You sent the sudo password"))
        }
        Task { await channel.respond(to: prompt.id, result: ["value": .string(value)]) }
    }

    /// Declines to answer; the agent carries on without it.
    public func skip(_ prompt: SecretPrompt) {
        guard let index = secrets.firstIndex(where: { $0.id == prompt.id }), let channel = channel() else { return }
        secrets.remove(at: index)
        switch prompt.kind {
        case .secret(let name, _): state.addNotice(String(localized: "You skipped \(name)"))
        case .sudo: state.addNotice(String(localized: "You skipped the sudo password"))
        }
        Task { await channel.respond(to: prompt.id, result: ["value": ""]) }
    }

    /// Removes a prompt the gateway withdrew. Returns whether `id` was one.
    func withdrawSecret(_ id: String, timedOut: Bool) -> Bool {
        guard let index = secrets.firstIndex(where: { $0.id == id }) else { return false }
        let prompt = secrets.remove(at: index)
        guard timedOut else { return true }
        switch prompt.kind {
        case .secret(let name, _): state.addNotice(String(localized: "Nobody answered in time, so \(name) wasn't set."))
        case .sudo: state.addNotice(String(localized: "Nobody answered in time, so the sudo password wasn't sent."))
        }
        return true
    }
}
