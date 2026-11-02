import Foundation

/// Sign-in for servers that use the provider's own web page (OAuth). The gateway runs the flow:
/// it hands back the provider's page, the provider sends the browser back to the gateway's own
/// callback, and the gateway keeps the token. The app opens the page and asks how it's going.
extension MCPServerList {
    private struct Flow: Decodable, Sendable {
        let flowId: String?
        let status: String
        let authorizationUrl: String?
        let error: String?
        let tools: [MCPTool]?
    }

    /// The gateway forgets a flow after 15 minutes; stop asking a little after that.
    private static let signInLimit = Duration.seconds(16 * 60)

    /// Starts signing in to `server`, opens the provider's page with `open`, and waits until the
    /// gateway has the token, the flow fails or it's cancelled. Success lists the server's tools.
    public func signIn(_ server: MCPServer, open: @escaping @MainActor (URL) -> Void) async {
        guard !server.isFromPlugin, flows[server.id] == nil, let auth = auth() else { return }
        clearMessages()
        signIns[server.id] = .starting
        let flow: Flow
        do {
            // The gateway waits up to 30 s for the provider before it answers.
            flow = try await auth.json(
                Flow.self, path: path("/api/mcp/servers/\(Self.escape(server.name))/auth"), method: "POST",
                timeout: 60)
        } catch {
            signIns[server.id] = .failed(AppModel.describe(error))
            return
        }
        if settle(server, flow) { return }
        // Cancelled while the gateway was starting it: let the gateway know too.
        if signIns[server.id] == nil, let flowID = flow.flowId {
            _ = try? await auth.json(Reply.self, path: "/api/mcp/oauth/flows/\(Self.escape(flowID))", method: "DELETE")
            return
        }
        guard let flowID = flow.flowId else {
            signIns[server.id] = .failed(String(localized: "The gateway didn't start the sign-in."))
            return
        }
        flows[server.id] = flowID
        if let page = flow.authorizationUrl.flatMap(URL.init(string:)),
            ["https", "http"].contains(page.scheme?.lowercased() ?? "")
        {
            signIns[server.id] = .waiting
            open(page)
        }
        await wait(for: server, flowID: flowID, auth: auth)
    }

    /// Stops a sign-in that's waiting, here and on the gateway.
    public func cancelSignIn(_ server: MCPServer) async {
        signIns[server.id] = nil
        guard let flowID = flows.removeValue(forKey: server.id), let auth = auth() else { return }
        _ = try? await auth.json(Reply.self, path: "/api/mcp/oauth/flows/\(Self.escape(flowID))", method: "DELETE")
    }

    private func wait(for server: MCPServer, flowID: String, auth: AuthSession) async {
        let deadline = ContinuousClock.now + Self.signInLimit
        while flows[server.id] == flowID, ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            guard flows[server.id] == flowID else { return }
            do {
                let flow = try await auth.json(Flow.self, path: "/api/mcp/oauth/flows/\(Self.escape(flowID))")
                if settle(server, flow) { return }
                if flow.status == "authorization_required", signIns[server.id] == .starting {
                    signIns[server.id] = .waiting
                }
            } catch GatewayError.http(status: 404, _) {
                flows[server.id] = nil
                signIns[server.id] = .failed(String(localized: "The sign-in expired. Try again."))
                return
            } catch {
                // A dropped connection mid-wait isn't the end of the sign-in; ask again.
                continue
            }
        }
        if flows[server.id] == flowID {
            flows[server.id] = nil
            signIns[server.id] = .failed(String(localized: "The sign-in expired. Try again."))
        }
    }

    /// Settles a flow that's approved or failed. False while it's still going.
    private func settle(_ server: MCPServer, _ flow: Flow) -> Bool {
        switch flow.status {
        case "approved":
            flows[server.id] = nil
            signIns[server.id] = nil
            checks[server.id] = .passed(flow.tools ?? [])
            notice = String(localized: "Signed in to “\(server.name)”.")
            return true
        case "error":
            flows[server.id] = nil
            signIns[server.id] = .failed(flow.error ?? String(localized: "The sign-in didn't finish."))
            return true
        default:
            return false
        }
    }
}
