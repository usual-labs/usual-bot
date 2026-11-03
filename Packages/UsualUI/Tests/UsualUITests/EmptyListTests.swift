import HermesKit
import Testing

@testable import UsualUI

struct EmptyListTests {
    @Test func offlineSaysWhatHappenedAndOffersTryAgain() {
        let offline = AppModel.Link.offline("The request timed out.")
        #expect(offline.emptyListText == "Can't reach your gateway. Check your connection or Tailscale.")
        #expect(offline.offersTryAgain)
    }

    @Test func connectingAndOnlineSayWhatsTrueWithoutTryAgain() {
        #expect(AppModel.Link.connecting.emptyListText == "Connecting…")
        #expect(!AppModel.Link.connecting.offersTryAgain)
        #expect(AppModel.Link.online(.legacy).emptyListText == "No agents on this gateway yet.")
        #expect(!AppModel.Link.online(.legacy).offersTryAgain)
    }
}
