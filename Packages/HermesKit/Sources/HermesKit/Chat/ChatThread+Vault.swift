import Foundation

extension ChatThread {
    /// Vault answers would cross the network unencrypted, so they need your say-so each time.
    public var vaultAnswersAreUnencrypted: Bool { gatewayIsUnencrypted() }

    func receive(_ prompt: VaultPrompt) {
        guard !vaultPrompts.contains(where: { $0.id == prompt.id }) else { return }
        vaultPrompts.append(prompt)
    }

    /// Takes over the prompts still waiting when the chat attaches. One that can't be shown is
    /// skipped, or it would hold the agent until its deadline.
    func adoptVaultPrompts(from requests: [ServerRequest]) {
        vaultPrompts = requests.compactMap(VaultPrompt.init)
        let unreadable = requests.filter { VaultPrompt.methods.contains($0.method) && VaultPrompt($0) == nil }
        guard !unreadable.isEmpty, let channel = channel() else { return }
        Task { for request in unreadable { await channel.respond(to: request.id, result: VaultPrompt.skipped) } }
    }

    /// Answers a vault prompt. Returns whether it went out: not while something is missing, and on
    /// an unencrypted address not unless `allowingUnencrypted`. The answer isn't kept or recorded.
    @discardableResult
    public func answer(
        _ prompt: VaultPrompt, secret: String, identifier: String? = nil, allowingUnencrypted: Bool = false
    ) -> Bool {
        guard let index = vaultPrompts.firstIndex(where: { $0.id == prompt.id }), let channel = channel(),
            allowingUnencrypted || !vaultAnswersAreUnencrypted,
            let value = prompt.value(secret: secret, identifier: identifier)
        else { return false }
        vaultPrompts.remove(at: index)
        state.addNotice(prompt.sentNotice)
        Task { await channel.respond(to: prompt.id, result: ["value": .string(value)]) }
        return true
    }

    /// Declines a vault prompt: an empty value tells the agent you skipped it.
    public func skip(_ prompt: VaultPrompt) {
        guard let index = vaultPrompts.firstIndex(where: { $0.id == prompt.id }), let channel = channel() else {
            return
        }
        vaultPrompts.remove(at: index)
        state.addNotice(prompt.skippedNotice)
        Task { await channel.respond(to: prompt.id, result: VaultPrompt.skipped) }
    }

    /// Takes away a vault prompt the gateway withdrew. `false` if `id` isn't one.
    func withdrawVaultPrompt(_ id: String, timedOut: Bool) -> Bool {
        guard let index = vaultPrompts.firstIndex(where: { $0.id == id }) else { return false }
        let prompt = vaultPrompts.remove(at: index)
        if timedOut { state.addNotice(prompt.timedOutNotice) }
        return true
    }
}
