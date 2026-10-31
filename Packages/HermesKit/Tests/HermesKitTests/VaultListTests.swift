import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// Shaped like `methods_vault.py`'s results. Secret-looking test values are made up.
private let listing: JSONValue = [
    "items": [
        [
            "id": "vault_1", "kind": "login", "label": "Example", "origin": "https://example.com",
            "created_at": "2026-10-30T09:15:00.123456+00:00", "identifier": "me@example.com",
            "identifier_type": "email", "has_otp": true, "backend": "local",
            // Not in the contract: a gateway bug must not put this anywhere the app can reach it.
            "password": "stray-secret",
        ],
        ["id": "vault_2", "kind": "payment", "label": "Card", "origin": .null, "created_at": "", "backend": "local"],
        ["id": "bw:3", "kind": "login", "label": "Team", "backend": "bitwarden"],
    ]
]

private let sourceRows: JSONValue = [
    "sources": [
        [
            "name": "local", "display_name": "Hermes vault", "enabled": true, "needs_unlock": false, "unlocked": true,
            "installed": true,
        ],
        [
            "name": "bitwarden", "display_name": "Bitwarden", "enabled": true, "needs_unlock": true, "unlocked": false,
            "installed": true,
        ],
    ]
]

private let loginDraft = VaultDraft.login(
    label: " Example ", origin: "example.com", identifierType: .email, identifier: " me@example.com ",
    password: "hunter2-test")

@MainActor
struct VaultListTests {
    private func make(unencrypted: Bool = false) async -> (VaultList, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        return (VaultList(profile: "scout", channel: { channel }, gatewayIsUnencrypted: { unencrypted }), gateway)
    }

    /// Loads the list, answering request numbers `first` and `first + 1`.
    private func load(_ list: VaultList, _ gateway: ScriptedGateway, first: Int = 0) async throws {
        async let loaded: Void = list.refresh()
        _ = try await gateway.answer(first, method: "vault.list", result: listing)
        _ = try await gateway.answer(first + 1, method: "vault.sources", result: sourceRows)
        await loaded
    }

    @Test func listsMetadataForTheProfile() async throws {
        let (list, gateway) = await make()
        try await load(list, gateway)

        #expect(gateway.socket.sent[0]["params"] == ["profile": "scout"])
        #expect(gateway.socket.sent[1]["params"] == ["profile": "scout"])
        #expect(list.phase == .ready)
        #expect(list.items.map(\.id) == ["vault_1", "vault_2", "bw:3"])
        let login = list.items[0]
        #expect(login.identifier == "me@example.com")
        #expect(login.hasOtp == true)
        #expect(login.added != nil)
        #expect(list.items[1].added == nil)
        #expect(list.items[0].isRemovable && !list.items[2].isRemovable)
        #expect(list.managers.map(\.displayName) == ["Bitwarden"])
        #expect(!String(reflecting: login).contains("stray-secret"))
    }

    @Test func aFailedFirstLoadSaysWhyAndALaterOneKeepsTheList() async throws {
        let (list, gateway) = await make()
        async let failed: Void = list.refresh()
        _ = try await gateway.answer(0, method: "vault.list", error: (5095, "vault file is corrupted"))
        await failed
        #expect(list.phase == .failed("vault file is corrupted"))

        try await load(list, gateway, first: 1)
        async let again: Void = list.refresh()
        _ = try await gateway.answer(3, method: "vault.list", error: (5095, "boom"))
        await again
        #expect(list.phase == .ready)
        #expect(list.items.count == 3)
    }

    @Test func anOlderGatewayAndNoConnectionAreSaidInWords() async throws {
        let (list, gateway) = await make()
        async let failed: Void = list.refresh()
        _ = try await gateway.answer(0, method: "vault.list", error: (-32601, "unknown method: vault.list"))
        await failed
        #expect(list.phase == .failed("This gateway's Hermes has no credential vault. Update Hermes on it."))

        let offline = VaultList(profile: "scout", channel: { nil }, gatewayIsUnencrypted: { false })
        await offline.refresh()
        #expect(offline.phase == .failed("The connection to the gateway closed."))
    }

    @Test func addsALoginAndReloads() async throws {
        let (list, gateway) = await make()
        async let saved = list.add(loginDraft)
        let params = try await gateway.answer(0, method: "vault.add", result: ["id": "vault_9"])
        try await load(list, gateway, first: 1)

        #expect(await saved)
        #expect(
            params == [
                "profile": "scout", "kind": "login", "label": "Example", "origin": "https://example.com",
                "secret": [
                    "identifier_type": "email", "identifier": "me@example.com", "password": "hunter2-test",
                ],
            ])
        #expect(list.problem == nil)
    }

    @Test func cardsAndAddressesUseTheVaultsFieldNames() {
        let card = VaultDraft.payment(
            label: "Card", cardNumber: "4242 4242 4242 4242", expMonth: "12", expYear: "2030", cvc: "123")
        #expect(card.isComplete)
        #expect(
            card.params == [
                "kind": "payment", "label": "Card",
                "secret": ["card_number": "4242424242424242", "exp_month": "12", "exp_year": "2030", "cvc": "123"],
            ])
        let address = VaultDraft.address(
            label: "Home", line1: "1 Example St", city: "Testville", postalCode: "00000", country: "Nowhere")
        #expect(address.isComplete)
        #expect(
            address.params["secret"] == [
                "address_line1": "1 Example St", "city": "Testville", "postal_code": "00000", "country": "Nowhere",
            ])
        #expect(!VaultDraft.address(label: "Home", line1: "", city: "", postalCode: "", country: "").isComplete)
    }

    @Test func aDraftDoesntPrintItsValues() {
        #expect("\(loginDraft)" == "VaultDraft(login)")
        #expect(!String(reflecting: loginDraft).contains("hunter2-test"))
    }

    @Test func loginsNeedARealSite() {
        let login = { (origin: String) in
            VaultDraft.login(
                label: "L", origin: origin, identifierType: .username, identifier: "me", password: "p")
        }
        #expect(login("https://example.com:8443").isComplete)
        #expect(login("example.com").origin == "https://example.com")
        #expect(!login("").isComplete)
        #expect(!login("ftp://example.com").isComplete)
    }

    @Test func aRefusedAddKeepsSecretsOutOfTheProblem() async throws {
        let (list, gateway) = await make()
        async let saved = list.add(loginDraft)
        _ = try await gateway.answer(
            0, method: "vault.add", error: (5095, "bad login me@example.com hunter2-test password=other-value"))

        #expect(await saved == false)
        let problem = try #require(list.problem)
        #expect(!problem.contains("hunter2-test"))
        #expect(!problem.contains("other-value"))
        #expect(!problem.contains("me@example.com"))
    }

    @Test func nothingIncompleteGoesOut() async throws {
        let (list, gateway) = await make()
        let draft = VaultDraft.login(label: "", origin: "", identifierType: .email, identifier: "", password: "")
        #expect(await list.add(draft) == false)
        #expect(gateway.socket.sent.isEmpty)
    }

    @Test func removesLocalItemsOnly() async throws {
        let (list, gateway) = await make()
        try await load(list, gateway)
        let managed = list.items[2]
        await list.remove(managed)
        #expect(gateway.socket.sent.count == 2)

        async let removed: Void = list.remove(list.items[0])
        let params = try await gateway.answer(2, method: "vault.remove", result: ["removed": true])
        await removed
        #expect(params == ["profile": "scout", "id": "vault_1"])
        #expect(list.items.map(\.id) == ["vault_2", "bw:3"])

        async let gone: Void = list.remove(list.items[0])
        _ = try await gateway.answer(3, method: "vault.remove", result: ["removed": false])
        await gone
        #expect(list.problem == "“Card” was already gone.")
    }

    @Test func aRefusedSwitchMovesBack() async throws {
        let (list, gateway) = await make()
        try await load(list, gateway)
        let bitwarden = try #require(list.managers.first)

        async let turnedOff: Void = list.setEnabled(false, for: bitwarden)
        let params = try await gateway.answer(2, method: "vault.source.set", error: (5095, "unknown vault source"))
        await turnedOff
        #expect(params == ["profile": "scout", "name": "bitwarden", "enabled": false])
        #expect(list.managers.first?.enabled == true)
        #expect(list.problem?.contains("unknown vault source") == true)
    }

    @Test func unlockAndLockNameTheManagerAndProfile() async throws {
        let (list, gateway) = await make()
        try await load(list, gateway)
        let bitwarden = try #require(list.managers.first)

        async let unlocked = list.unlock(bitwarden, password: "master-test")
        let params = try await gateway.answer(
            2, method: "vault.unlock", result: ["name": "bitwarden", "unlocked": true])
        try await load(list, gateway, first: 3)
        #expect(await unlocked)
        #expect(params == ["profile": "scout", "name": "bitwarden", "password": "master-test"])

        async let locked: Void = list.lock(bitwarden)
        let lockParams = try await gateway.answer(5, method: "vault.lock", result: ["locked": true])
        try await load(list, gateway, first: 6)
        await locked
        #expect(lockParams == ["profile": "scout", "name": "bitwarden"])
    }

    @Test func aFailedUnlockKeepsTheMasterPasswordOutOfTheProblem() async throws {
        let (list, gateway) = await make()
        try await load(list, gateway)
        let bitwarden = try #require(list.managers.first)

        async let unlocked = list.unlock(bitwarden, password: "master-test")
        _ = try await gateway.answer(2, method: "vault.unlock", error: (5095, "bw said: wrong master-test"))
        #expect(await unlocked == false)
        #expect(list.problem == "Couldn't unlock Bitwarden: bw said: wrong [hidden]")
    }

    @Test func anUnencryptedAddressSendsNoSecretWithoutYourSaySo() async throws {
        let (list, gateway) = await make(unencrypted: true)
        try await load(list, gateway)
        let bitwarden = try #require(list.managers.first)

        #expect(await list.add(loginDraft) == false)
        #expect(await list.unlock(bitwarden, password: "master-test") == false)
        #expect(gateway.socket.sent.count == 2)

        async let saved = list.add(loginDraft, allowingUnencrypted: true)
        _ = try await gateway.answer(2, method: "vault.add", result: ["id": "vault_9"])
        try await load(list, gateway, first: 3)
        #expect(await saved)
    }
}

struct VaultRedactionTests {
    @Test func takesOutSecretsPairsAndCardNumbers() {
        #expect(VaultRedaction.scrub("wrong Hunter2", removing: ["hunter2"]) == "wrong [hidden]")
        #expect(VaultRedaction.scrub("abcdef abc", removing: ["abc", "abcdef"]) == "[hidden] [hidden]")
        #expect(VaultRedaction.scrub("password: oops") == "password: [hidden]")
        #expect(VaultRedaction.scrub(#""cvc"="999""#) == #""cvc"=[hidden]"#)
        #expect(VaultRedaction.scrub("card 4242 4242 4242 4242 refused") == "card [hidden] refused")
        #expect(VaultRedaction.scrub("nothing here, 2 items") == "nothing here, 2 items")
        #expect(VaultRedaction.scrub("fine", removing: [""]) == "fine")
    }
}

#if DEBUG
    struct FrameRedactionTests {
        @Test func blanksAnswersAndVaultSecrets() {
            #expect(
                FrameRecorder.redacted(["id": "srq-1", "result": ["value": "typed"]])
                    == ["id": "srq-1", "result": ["value": ""]])
            #expect(
                FrameRecorder.redacted(["method": "vault.unlock", "params": ["name": "bw", "password": "typed"]])
                    == ["method": "vault.unlock", "params": ["name": "bw", "password": ""]])
            #expect(
                FrameRecorder.redacted([
                    "method": "vault.add", "params": ["label": "L", "secret": ["password": "typed"]],
                ])
                    == ["method": "vault.add", "params": ["label": "L", "secret": ""]])
        }

        @Test func leavesOtherFramesAlone() {
            let frames: [JSONValue] = [
                ["id": 1, "method": "vault.list", "params": ["profile": "scout"]],
                ["id": "srq-1", "result": ["choice": "once"]],
                ["id": 2, "method": "prompt.submit", "params": ["text": "hello", "password": "kept in a message"]],
            ]
            #expect(frames.map(FrameRecorder.redacted) == frames)
        }
    }

    /// One at a time: the recorder's observer is shared, and these tests check what it saw.
    @MainActor
    @Suite(.serialized)
    struct VaultRecordingTests {
        /// Lines the recorder would write while `body` ran. Other suites' frames may be among them.
        private func recorded(during body: () async throws -> Void) async rethrows -> [String] {
            let lines = Mutex<[String]>([])
            FrameRecorder.observer.withLock { $0 = { text in lines.withLock { $0.append(text) } } }
            defer { FrameRecorder.observer.withLock { $0 = nil } }
            try await body()
            return lines.withLock { $0 }
        }

        @Test func secretsAndTheirRepliesAreNeverRecorded() async throws {
            let gateway = ScriptedGateway()
            let channel = JSONRPCChannel(socket: gateway.socket)
            await channel.start()
            let list = VaultList(profile: "record-test", channel: { channel }, gatewayIsUnencrypted: { false })
            let bitwarden = VaultSource(
                name: "bitwarden", displayName: "Bitwarden", enabled: true, needsUnlock: true, unlocked: false,
                installed: true)

            let lines = try await recorded {
                async let saved = list.add(loginDraft)
                _ = try await gateway.answer(0, method: "vault.add", error: (5095, "rejected hunter2-test"))
                _ = await saved
                async let unlocked = list.unlock(bitwarden, password: "master-test")
                _ = try await gateway.answer(1, method: "vault.unlock", error: (5095, "rejected master-test"))
                _ = await unlocked
            }
            // The calls are there, so a change to the frame's shape can't pass unnoticed.
            let calls = lines.filter { $0.contains("record-test") }
            #expect(calls.count == 2)
            #expect(!lines.contains { $0.contains("hunter2-test") || $0.contains("master-test") })
        }

        @Test func answersAreRecordedBlank() async throws {
            let gateway = ScriptedGateway()
            let channel = JSONRPCChannel(socket: gateway.socket)
            await channel.start()
            let thread = ChatThread(contactID: "scout", channel: { channel })
            thread.gatewayIsUnencrypted = { false }
            let prompt = VaultPrompt(id: "srq-record", sessionID: "s", kind: .code(site: nil, hint: nil))
            thread.receive(prompt)

            let lines = try await recorded {
                thread.answer(prompt, secret: "answer-marker-test")
                try await waitUntil { gateway.socket.sent.count == 1 }
            }
            #expect(gateway.socket.sent[0]["result"] == ["value": "answer-marker-test"])  // Sent as typed.
            #expect(lines.contains { $0.contains("srq-record") })
            #expect(!lines.contains { $0.contains("answer-marker-test") })
        }
    }
#endif
