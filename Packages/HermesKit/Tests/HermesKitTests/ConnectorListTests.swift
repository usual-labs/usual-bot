import Foundation
import Testing

@testable import HermesKit

@MainActor
struct ConnectorListTests {
    private func list() async -> (ConnectorList, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        return (ConnectorList(profile: "scout", channel: { channel }, pollInterval: .milliseconds(10)), gateway)
    }

    private let listed: JSONValue = [
        "available": true,
        "connectors": [
            ["connector": "gmail", "enabled": true, "connected": true, "connection_status": "active"],
            ["connector": "slack", "enabled": true, "connected": false, "status_reason": "Token revoked"],
            ["connector": "jira", "enabled": false, "connected": false],
        ],
    ]
    private let catalog: JSONValue = [
        "connectors": [
            ["slug": "gmail", "name": "Gmail", "description": "Email", "category": "mail"],
            ["slug": "slack", "name": "Slack", "description": "Chat", "category": "chat"],
            ["slug": "notion", "name": "Notion", "description": "Pages", "category": "docs"],
        ]
    ]
    private let accounts: JSONValue = [
        "accounts": [
            [
                "connection_id": "acc-1", "connector": "gmail", "status": "active", "label": "me@example.com",
                "active": true, "disabled": false, "created_at": "", "updated_at": "",
            ],
            [
                "connection_id": "acc-old", "connector": "gmail", "status": "inactive", "label": "old",
                "active": false, "disabled": true, "created_at": "", "updated_at": "",
            ],
        ]
    ]

    private func load(_ list: ConnectorList, _ gateway: ScriptedGateway, from index: Int = 0) async throws {
        let refresh = Task { await list.refresh() }
        let params = try await gateway.answer(index, method: "connectors.list", result: listed)
        #expect(params == ["owner": ["type": "account"], "profile": "scout"])
        // The catalog and the accounts are read together, in either order.
        for offset in 1...2 {
            try await waitUntil { gateway.socket.sent.count > index + offset }
            let method = gateway.socket.sent[index + offset]["method"]?.stringValue ?? ""
            _ = try await gateway.answer(
                index + offset, method: method, result: method == "connectors.catalog" ? catalog : accounts)
        }
        await refresh.value
    }

    @Test func listsTheCatalogWithConnectedAppsFirst() async throws {
        let (list, gateway) = await list()
        try await load(list, gateway)
        #expect(list.phase == .ready)
        #expect(list.connectors.map(\.slug) == ["gmail", "notion", "slack"])
        #expect(list.connectors[0].isConnected)
        #expect(list.connectors[0].accountIDs == ["acc-1"])
        #expect(list.connectors[2].statusReason == "Token revoked")
    }

    @Test func aGatewayWithoutConnectorsSaysSo() async throws {
        let (list, gateway) = await list()
        let refresh = Task { await list.refresh() }
        _ = try await gateway.answer(0, method: "connectors.list", result: ["available": false, "connectors": []])
        await refresh.value
        #expect(list.phase == .unavailable)
    }

    @Test func connectOpensTheVendorPageAndWaitsForHermes() async throws {
        let (list, gateway) = await list()
        try await load(list, gateway)
        let notion = try #require(list.connectors.first { $0.slug == "notion" })
        var opened: [URL] = []
        let connecting = Task { await list.connect(notion) { opened.append($0) } }
        let params = try await gateway.answer(
            3, method: "connectors.connect",
            result: [
                "op_id": "acct-op", "seq": 2, "deadline_at": 1_800_000_000, "settled": false,
                "targets": [
                    [
                        "name": "notion", "kind": "connector", "action": "connect", "state": "initiated",
                        "connect_url": "https://connect.example.com/notion",
                    ]
                ],
            ])
        #expect(params == ["owner": ["type": "account"], "profile": "scout", "connectors": ["notion"]])
        try await waitUntilOnMain { list.connecting["notion"] == .waiting }
        #expect(opened == [URL(string: "https://connect.example.com/notion")!])

        let status = try await gateway.answer(
            4, method: "connectors.operation.status",
            result: [
                "op_id": "acct-op", "seq": 3, "deadline_at": 1_800_000_000, "settled": true,
                "targets": [["name": "notion", "kind": "connector", "action": "connect", "state": "connected"]],
            ])
        #expect(status == ["owner": ["type": "account"], "profile": "scout", "op_id": "acct-op"])
        await connecting.value
        #expect(list.connecting["notion"] == nil)
        #expect(list.notice == "Connected Notion.")
        #expect(opened.count == 1)
    }

    @Test func aFailedConnectSaysWhy() async throws {
        let (list, gateway) = await list()
        try await load(list, gateway)
        let slack = try #require(list.connectors.first { $0.slug == "slack" })
        let connecting = Task { await list.connect(slack) { _ in } }
        _ = try await gateway.answer(
            3, method: "connectors.connect",
            result: [
                "op_id": "acct-op", "seq": 2, "deadline_at": 1_800_000_000, "settled": false,
                "targets": [
                    [
                        "name": "slack", "kind": "connector", "action": "connect", "state": "failed",
                        "detail": "not allowed by your organization's policy",
                    ]
                ],
            ])
        await connecting.value
        #expect(list.connecting["slack"] == .failed("not allowed by your organization's policy"))
    }

    @Test func disconnectRemovesEachLiveAccount() async throws {
        let (list, gateway) = await list()
        try await load(list, gateway)
        let gmail = try #require(list.connectors.first { $0.slug == "gmail" })
        let disconnecting = Task { await list.disconnect(gmail) }
        let params = try await gateway.answer(
            3, method: "connectors.accounts.remove",
            result: ["connection_id": "acc-1", "connector": "gmail", "status": "removed"])
        #expect(params == ["profile": "scout", "connection_id": "acc-1"])
        try await load(list, gateway, from: 4)
        await disconnecting.value
        #expect(list.notice == "Disconnected Gmail.")
    }
}
