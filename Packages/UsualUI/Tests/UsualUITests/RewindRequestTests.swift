import Testing

@testable import HermesKit
@testable import UsualUI

struct RewindRequestTests {
    private func cost(messages: Int, fromHermes: Int = 0, steps: Int = 0, reachesBack: Bool) -> ChatThread.RewindCost {
        ChatThread.RewindCost(messages: messages, fromHermes: fromHermes, steps: steps, reachesBack: reachesBack)
    }

    private let item = TranscriptItem(id: 0, content: .user("Plan my week"))

    @Test func anEarlierEditSaysHowMuchGoesAndThatItCantComeBack() {
        let request = RewindRequest(
            kind: .edit(item, text: "Plan my month"), cost: cost(messages: 6, fromHermes: 1, reachesBack: true))
        #expect(request.title == "Replace this message and remove the 6 after it?")
        let message = request.message(agentName: "Scout")
        #expect(message.contains("can't be brought back"))
        #expect(message.contains("One of them came from Hermes itself"))
        #expect(message.contains("Anything Scout already did stays done"))
        #expect(request.confirmLabel == "Replace and Remove")
        #expect(RewindRequest.editingLabel(for: request.cost) == "Editing a message. The 6 after it go too.")
    }

    /// The last exchange alone asks only when the Bot acted in it.
    @Test func tryingAgainSaysTheBotsStepsStayDone() {
        let acted = cost(messages: 1, steps: 2, reachesBack: false)
        #expect(acted.needsConfirmation)
        #expect(!cost(messages: 1, reachesBack: false).needsConfirmation)
        let request = RewindRequest(kind: .tryAgain, cost: acted)
        #expect(request.title == "Try this reply again?")
        #expect(request.message(agentName: "Scout").contains("That stays done, and it may do it again."))
        #expect(RewindRequest.editingLabel(for: acted) == "Editing your last message")
    }
}
