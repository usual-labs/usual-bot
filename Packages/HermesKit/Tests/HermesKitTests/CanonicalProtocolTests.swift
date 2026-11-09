import Foundation
import Testing

@testable import HermesKit

/// The bookkeeping and translation for the canonical session protocol, without a socket.
struct CanonicalProtocolTests {
    private func attached(_ session: String = "local-1", profile: String = "scout") -> CanonicalProtocol {
        var canonical = CanonicalProtocol()
        canonical.absorbSnapshot(
            [
                "session_id": .string(session), "execution_generation": 4, "revision": 7,
                "subscription_id": "sub-1", "replay_epoch": "e1", "last_sequence": 20,
            ], profile: profile)
        return canonical
    }

    private func frame(_ type: String, seq: Int? = nil, epoch: String = "e1", _ payload: JSONValue = [:]) -> JSONValue {
        var params: [String: JSONValue] = ["type": .string(type), "session_id": "local-1", "payload": payload]
        if let seq {
            params["seq"] = .number(Double(seq))
            params["replay_epoch"] = .string(epoch)
        }
        return .object(params)
    }

    private func events(_ inbound: [CanonicalProtocol.Inbound]) -> [GatewayEvent] {
        inbound.compactMap { if case .event(let event) = $0 { event } else { nil } }
    }

    @Test func callsAboutASessionCarryItsProfile() {
        let canonical = attached()
        #expect(
            canonical.routed("prompt.submit", ["session_id": "local-1", "text": "Hi"])
                == ["session_id": "local-1", "text": "Hi", "profile": "scout"])
        // A session card's answer names its session inside `owner`.
        #expect(
            canonical.routed("connection.respond", ["owner": ["type": "session", "session_id": "local-1"]])["profile"]
                == "scout")
        // Methods with closed keys, and sessions it hasn't attached, are left alone.
        #expect(canonical.routed("connectors.list", ["session_id": "local-1"]) == ["session_id": "local-1"])
        #expect(canonical.routed("prompt.submit", ["session_id": "local-9"]) == ["session_id": "local-9"])
        #expect(
            canonical.routed("prompt.submit", ["session_id": "local-1", "profile": "ops"])
                == ["session_id": "local-1", "profile": "ops"])
    }

    @Test func fencesOnlyMoveForward() {
        var canonical = attached()
        canonical.absorbFences(["revision": 9, "execution_generation": 5], session: "local-1")
        // An exact retry's receipt replays its original, older numbers.
        canonical.absorbFences(["revision": 8, "execution_generation": 3], session: "local-1")
        #expect(canonical.session("local-1")?.revision == 9)
        #expect(canonical.session("local-1")?.generation == 5)
        // Every frame of a turn names its generation.
        _ = canonical.inbound(
            ["type": "message.start", "session_id": "local-1", "execution_generation": 6, "payload": [:]])
        #expect(canonical.session("local-1")?.generation == 6)
    }

    @Test func framesTheSnapshotAlreadyHasAreDropped() {
        var canonical = attached()
        #expect(canonical.inbound(frame("message.delta", seq: 20, ["text": "old"])).isEmpty)
        #expect(events(canonical.inbound(frame("message.delta", seq: 21, ["text": "new"]))).count == 1)
        #expect(canonical.inbound(frame("message.delta", seq: 21, ["text": "new"])).isEmpty)
        // New numbering after the gateway's replay ring started over.
        #expect(events(canonical.inbound(frame("message.delta", seq: 1, epoch: "e2", ["text": "again"]))).count == 1)
        #expect(canonical.session("local-1")?.replayEpoch == "e2")
    }

    @Test func approvalEventsBecomeRequestsAndTheirAnswersCalls() throws {
        var canonical = attached()
        let inbound = canonical.inbound(
            frame(
                "approval.request",
                [
                    "kind": "approval", "prompt_id": "p1", "execution_generation": 4, "command": "rm -rf build",
                    "description": "delete in root path", "choices": ["once", "deny", "session", "always"],
                ]))
        guard case .request(let request) = try #require(inbound.first) else {
            Issue.record("Expected a request")
            return
        }
        let approval = try #require(ApprovalPrompt(request))
        #expect(approval.id == "p1")
        #expect(approval.sessionID == "local-1")
        #expect(approval.command == "rm -rf build")
        #expect(approval.choices == [.once, .deny, .session, .always])

        let answered = canonical.answer("p1", result: ["choice": "once"])
        let answer = try #require(answered)
        #expect(answer.method == "approval.respond")
        #expect(
            answer.params == ["session_id": "local-1", "execution_generation": 4, "prompt_id": "p1", "choice": "once"])
        // Answered once only; a request the gateway sent as one is answered as a response.
        #expect(canonical.answer("p1", result: ["choice": "once"]) == nil)
        #expect(canonical.answer("srq-1", result: ["value": ""]) == nil)
    }

    @Test func questionsAreAskedOneAtATimeAndSkippedWithAnEmptyAnswer() throws {
        var canonical = attached()
        let inbound = canonical.inbound(
            frame(
                "clarify.request",
                [
                    "kind": "clarify", "prompt_id": "q1", "execution_generation": 4, "question": "Which pets?",
                    "choices": ["Cats (Recommended)", "Dogs"], "multi_select": true,
                ]))
        guard case .request(let request) = try #require(inbound.first) else {
            Issue.record("Expected a request")
            return
        }
        let prompt = try #require(ClarifyPrompt(request))
        #expect(prompt.questions.map(\.id) == ["q1"])
        #expect(prompt.questions[0].allowsMultiple)

        let reply = canonical.answer(
            "q1", result: ["answers": ["q1": #"["Cats (Recommended)","Dogs"]"#], "outcome": "submitted"])
        let answered = try #require(reply)
        #expect(answered.method == "clarify.respond")
        #expect(answered.params["answer"] == #"["Cats (Recommended)","Dogs"]"#)

        _ = canonical.inbound(
            frame(
                "clarify.request", ["kind": "clarify", "prompt_id": "q2", "execution_generation": 4, "question": "?"]))
        #expect(canonical.answer("q2", result: ["outcome": "cancelled"])?.params["answer"] == "")
    }

    @Test func aSettledPromptIsWithdrawn() {
        var canonical = attached()
        _ = canonical.inbound(
            frame("approval.request", ["kind": "approval", "prompt_id": "p1", "execution_generation": 4]))
        let withdrawn = events(
            canonical.inbound(frame("approval.settled", ["prompt_id": "p1", "execution_generation": 4])))
        #expect(withdrawn.map(\.type) == ["request.cancel"])
        #expect(withdrawn.first?.payload == ["id": "p1", "reason": "resolved"])
        #expect(canonical.answer("p1", result: ["choice": "once"]) == nil)
    }

    @Test func eventsTakeTheLegacyShape() {
        var canonical = attached()
        // The end of one stretch of streamed text.
        #expect(
            events(canonical.inbound(frame("message.delta", ["text": .null]))).map(\.type) == ["message.interim"])
        // A queued message taken back ran no turn.
        #expect(canonical.inbound(frame("message.complete", ["text": "", "outcome": "cancelled"])).isEmpty)
        #expect(
            events(canonical.inbound(frame("message.complete", ["text": "Done", "status": "complete"]))).count == 1)

        let failed = events(
            canonical.inbound(
                frame("tool.complete", ["tool_id": "t1", "is_error": true, "result": #"{"error": "no such file"}"#])))
        #expect(failed.first?.payload["result"]?["error"] == "no such file")
        let plain = events(
            canonical.inbound(frame("tool.complete", ["tool_id": "t2", "is_error": true, "result": "Timed out"])))
        #expect(plain.first?.payload["result"] == ["error": "Timed out"])
        let worked = events(
            canonical.inbound(
                frame(
                    "tool.complete",
                    ["tool_id": "t3", "is_error": false, "result": #"{"output": "ok", "error": null}"#])))
        #expect(worked.first?.payload["result"] == ["output": "ok", "error": .null])
    }

    @Test func aSnapshotTakesTheLegacyShape() {
        var canonical = CanonicalProtocol()
        let result: JSONValue = [
            "session_id": "local-1", "running": true, "replay_epoch": "e1", "last_sequence": 3,
            "messages": [["role": "user", "content": "raw"]],
            "display_messages": [
                [
                    "role": "user", "text": "Plan my week", "row_id": 5,
                    "display_metadata": ["submission_id": "in-1"],
                ]
            ],
            "pending": [["admission_id": "a1", "status": "started", "input_id": "in-1", "text": "Plan my week"]],
            "prompts": [
                [
                    "kind": "approval", "prompt_id": "p1", "execution_generation": 2, "command": "ls",
                    "choices": ["once", "deny"],
                ]
            ],
            "open_requests": [["id": "srq-1", "method": "sudo", "params": ["session_id": "local-1"]]],
        ]
        canonical.absorbSnapshot(result, profile: "scout")
        let legacy = canonical.legacySnapshot(result, replySoFar: "Monday: ")
        #expect(legacy["messages"] == result["display_messages"])
        #expect(
            CanonicalProtocol.rows(legacy["open_requests"]).compactMap { $0["id"]?.stringValue } == ["srq-1", "p1"])
        // The running prompt is stored already, so only the reply so far is new.
        #expect(legacy["inflight"] == ["user": "", "assistant": "Monday: "])
        #expect(canonical.answer("p1", result: ["choice": "deny"])?.method == "approval.respond")
    }

    @Test func theReplySoFarIsReadFromReplayFrames() {
        let frames: JSONValue = [
            ["type": "message.delta", "admission_id": "a0", "payload": ["text": "Earlier turn"]],
            ["type": "message.delta", "admission_id": "a1", "payload": ["text": "Mon"]],
            ["type": "tool.start", "admission_id": "a1", "payload": ["name": "calendar"]],
            ["type": "message.delta", "admission_id": "a1", "payload": ["text": .null]],
            ["type": "message.delta", "admission_id": "a1", "payload": ["text": "day"]],
        ]
        #expect(CanonicalProtocol.replyText(in: frames, admission: "a1") == "Monday")
    }

    /// Asked after the attach's snapshot was taken, so only the replay frames have them.
    @Test func promptsStillWaitingAreReadFromReplayFrames() {
        let frames: JSONValue = [
            ["type": "approval.request", "payload": ["kind": "approval", "prompt_id": "p1", "command": "ls"]],
            ["type": "approval.settled", "payload": ["prompt_id": "p1"]],
            ["type": "clarify.request", "payload": ["kind": "clarify", "prompt_id": "q1", "question": "?"]],
        ]
        #expect(CanonicalProtocol.waitingPrompts(in: frames).map { $0["prompt_id"] } == ["q1"])
    }

    @Test func modelSwitchesTakeTheLegacyShape() {
        #expect(CanonicalProtocol.modelPick("gpt-6 --provider openai --session")! == ("gpt-6", "openai"))
        #expect(CanonicalProtocol.modelPick("gpt-6")! == ("gpt-6", nil))
        #expect(CanonicalProtocol.modelPick("two words --session") == nil)

        #expect(
            CanonicalProtocol.legacyModelResult([
                "status": "confirmation_required", "confirm": "t1", "confirm_message": "It costs more.",
            ]) == ["confirm_required": true, "confirm_message": "It costs more."])
        #expect(CanonicalProtocol.legacyModelResult(["status": "deferred"]) == ["deferred": true])
        #expect(
            CanonicalProtocol.legacyModelResult(["operation": "model", "warnings": ["No vision."]])
                == ["warning": "No vision."])
    }

    @Test func refusalsAreInWords() {
        #expect(
            CanonicalRefusal(code: 4001, reason: "queue_full", message: "queue_full", detail: nil).gatewayError
                == .rpc(code: 4001, message: "Too many messages are waiting. Let the agent catch up first."))
        #expect(
            CanonicalRefusal(
                code: 4001, reason: "unsupported_command", message: "unsupported_command", detail: "Try /help"
            )
            .gatewayError == .rpc(code: 4001, message: "Try /help"))
        // Connector refusals keep the gateway's own message.
        #expect(
            CanonicalRefusal(
                code: 4000, reason: "INVALID_PARAMS", message: "Connector parameters are invalid.", detail: nil
            )
            .gatewayError == .rpc(code: 4000, message: "Connector parameters are invalid."))
    }
}
