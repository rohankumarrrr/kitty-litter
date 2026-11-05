import ShadesCore
@testable import ShadesT3
import XCTest

final class T3WireTests: XCTestCase {
    private func exit(_ frame: String) throws -> T3Wire.Exit<T3Wire.TurnItemResult> {
        let frames = try T3Wire.frames(T3Wire.ExitFrame<T3Wire.TurnItemResult>.self, in: Data(frame.utf8))
        return try XCTUnwrap(frames.first?.exit)
    }

    private func decoded(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Effort maps to each provider's own option

    func testCodexEffortUsesReasoningEffort() {
        let selection = T3Wire.ModelSelection(.quick)
        XCTAssertEqual(selection.instanceId, "codex")
        XCTAssertEqual(selection.model, "gpt-6.1-sol")
        XCTAssertEqual(selection.options, [.init(id: "reasoningEffort", value: "medium")])
    }

    func testClaudeEffortUsesEffort() {
        let selection = T3Wire.ModelSelection(.frontier)
        XCTAssertEqual(selection.instanceId, "claudeAgent")
        XCTAssertEqual(selection.options, [.init(id: "effort", value: "xhigh")])
    }

    func testNoEffortSendsNoOptions() {
        let selection = T3Wire.ModelSelection(ModelChoice(provider: "codex", model: "m", effort: ""))
        XCTAssertNil(selection.options)
    }

    // MARK: What goes out

    func testRequestFrame() throws {
        let frame = T3Wire.request(id: "9", method: T3Wire.Method.dispatchCommand, payload: T3Wire.encode(T3Wire.ArchiveThread(commandId: "c", threadId: "t")))
        let json = try decoded(frame)
        XCTAssertEqual(json["_tag"] as? String, "Request")
        XCTAssertEqual(json["id"] as? String, "9")
        XCTAssertEqual(json["tag"] as? String, "orchestration.dispatchCommand")
        XCTAssertEqual((json["headers"] as? [Any])?.count, 0)
        let payload = try XCTUnwrap(json["payload"] as? [String: String])
        XCTAssertEqual(payload, ["type": "thread.archive", "commandId": "c", "threadId": "t"])
    }

    func testAckAndInterruptFrames() throws {
        XCTAssertEqual(try decoded(T3Wire.ack(requestID: "3")) as? [String: String], ["_tag": "Ack", "requestId": "3"])
        XCTAssertEqual(try decoded(T3Wire.interrupt(requestID: "3")) as? [String: String], ["_tag": "Interrupt", "requestId": "3"])
    }

    func testLaunchPayload() throws {
        let launch = T3Wire.LaunchThread(
            commandId: "c",
            threadId: "t",
            projectId: "p",
            title: "Title",
            generateTitle: false,
            modelSelection: .init(.frontier),
            runtimeMode: RuntimeMode.approvalRequired.rawValue,
            initialMessage: .init(messageId: "m", text: "hi", attachments: [.init(id: "a", name: "s.png", mimeType: "image/png", sizeBytes: 3)])
        )
        let json = try decoded(T3Wire.encode(launch))
        XCTAssertEqual(json["runtimeMode"] as? String, "approval-required")
        XCTAssertEqual(json["interactionMode"] as? String, "default")
        XCTAssertEqual((json["workspaceStrategy"] as? [String: String])?["type"], "root")
        let message = try XCTUnwrap(json["initialMessage"] as? [String: Any])
        let attachment = try XCTUnwrap((message["attachments"] as? [[String: Any]])?.first)
        XCTAssertEqual(attachment["type"] as? String, "image")
        XCTAssertEqual(attachment["id"] as? String, "a")
        XCTAssertEqual(attachment["sizeBytes"] as? Int, 3)
    }

    func testFollowUpGetsItsOwnRun() throws {
        let message = T3Wire.DispatchMessage(commandId: "c", threadId: "t", messageId: "m", text: "hi", attachments: [], modelSelection: .init(.quick))
        let json = try decoded(T3Wire.encode(message))
        XCTAssertEqual(json["type"] as? String, "message.dispatch")
        XCTAssertEqual((json["dispatchMode"] as? [String: String])?["type"], "start_immediately")
        XCTAssertNil(json["deliveryIntent"], "A delivery intent could steer a run already going")
    }

    func testRespondCommand() throws {
        let command = T3Wire.RespondToRequest(commandId: "c", threadId: "t", requestId: "r", decision: ApprovalDecision.acceptForSession.rawValue)
        let json = try decoded(T3Wire.encode(command)) as? [String: String]
        XCTAssertEqual(json, ["type": "runtime-request.respond", "commandId": "c", "threadId": "t", "requestId": "r", "decision": "acceptForSession"])
    }

    // MARK: IDs and links

    func testApprovalItemIDMatchesWhatTheServerBuilds() {
        XCTAssertEqual(T3Wire.approvalItemID(requestID: T3Fixtures.approvalRequestID), T3Fixtures.approvalItemID)
    }

    func testThreadLinkEncodesIDs() {
        let link = T3Wire.threadLink(environmentID: "env-1", threadID: "mcp:launch:abc")
        XCTAssertEqual(link?.absoluteString, "t3code://threads/env-1/mcp%3Alaunch%3Aabc")
    }

    // MARK: What comes back

    func testDispatchFailureCarriesTheServersReason() throws {
        let exit = try exit(T3Fixtures.dispatchFailure)
        XCTAssertFalse(exit.isSuccess)
        XCTAssertFalse(exit.isProtocolMismatch)
        XCTAssertEqual(exit.failureMessage, "No orchestration projection exists for thread not-a-thread.")
    }

    func testUnknownMethodAndBadPayloadMeanProtocolMismatch() throws {
        XCTAssertTrue(try exit(T3Fixtures.unknownMethod).isProtocolMismatch)
        XCTAssertTrue(try exit(T3Fixtures.badPayload).isProtocolMismatch)
    }

    func testInterruptIsNotAFailureOfOurs() throws {
        let exit = try exit(T3Fixtures.interrupted)
        XCTAssertTrue(exit.isInterruptOnly)
        XCTAssertFalse(exit.isProtocolMismatch)
    }

    func testMissingItemDecodes() throws {
        let exit = try exit(T3Fixtures.missingItem)
        XCTAssertTrue(exit.isSuccess)
        XCTAssertNil(exit.value?.item)
    }

    func testFramesCanComeAsAList() throws {
        let frames = try T3Wire.frames(T3Wire.FrameHeader.self, in: Data(#"[{"_tag":"Pong"},{"_tag":"Ack","requestId":"1"}]"#.utf8))
        XCTAssertEqual(frames.map(\._tag), ["Pong", "Ack"])
    }

    func testUnknownStreamItemsAreSkipped() throws {
        let frame = #"{"_tag":"Chunk","requestId":"1","values":[{"kind":"from.the.future"},{"nonsense":true},{"kind":"thread.removed","sequence":1,"location":"active","threadId":"t"}]}"#
        let chunk = try XCTUnwrap(T3Wire.frames(T3Wire.ChunkFrame<T3Wire.ShellItem>.self, in: Data(frame.utf8)).first)
        XCTAssertEqual(chunk.items.count, 2)
        guard case .other = chunk.items[0], case .threadRemoved(id: "t") = chunk.items[1] else {
            return XCTFail("Expected an unknown item and then the removal")
        }
    }

    func testDatesParseWithAndWithoutFractions() {
        XCTAssertNotNil(T3Wire.parseDate("2026-11-05T03:44:48.210Z"))
        XCTAssertNotNil(T3Wire.parseDate("2026-11-05T03:44:48Z"))
        XCTAssertNil(T3Wire.parseDate("yesterday"))
    }

    // MARK: Compatibility and sign-in

    func testOnlyProtocolTwoIsCompatible() throws {
        func environment(_ version: Int?) throws -> T3Wire.Environment {
            let value = version.map(String.init) ?? "null"
            let json = #"{"environmentId":"e","serverVersion":"0.1.6","orchestrationProtocolVersion":\#(value)}"#
            return try T3Wire.decoder().decode(T3Wire.Environment.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try environment(2).isCompatible)
        XCTAssertFalse(try environment(3).isCompatible)
        XCTAssertFalse(try environment(nil).isCompatible)
    }

    func testSessionNeedsBothScopes() throws {
        func state(_ json: String) throws -> T3Wire.SessionState {
            try T3Wire.decoder().decode(T3Wire.SessionState.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try state(#"{"authenticated":true,"scopes":["orchestration:read","orchestration:operate"]}"#).isUsable)
        XCTAssertFalse(try state(#"{"authenticated":true,"scopes":["orchestration:read"]}"#).isUsable)
        XCTAssertFalse(try state(#"{"authenticated":false}"#).isUsable)
    }

    func testIssuedSessionDecodes() throws {
        let json = #"{"sessionId":"s","token":"t","method":"bearer-access-token","scopes":[],"subject":"cli-issued-session","client":{"label":"Shades","deviceType":"bot"},"expiresAt":"2026-12-05T05:59:24.046Z"}"#
        let session = try T3Wire.decoder().decode(T3Wire.IssuedSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.sessionId, "s")
        XCTAssertNotNil(session.expiresAt)
    }

    // MARK: Approval words

    func testCommandsLoseTheirShellWrapper() {
        XCTAssertEqual(T3Wire.unwrappedCommand("/bin/zsh -lc 'echo hi > /tmp/x'"), "echo hi > /tmp/x")
        XCTAssertEqual(T3Wire.unwrappedCommand("bash -c 'ls'"), "ls")
        XCTAssertEqual(T3Wire.unwrappedCommand(#"/bin/zsh -lc 'echo '\''quoted'\'''"#), "echo 'quoted'")
        XCTAssertEqual(T3Wire.unwrappedCommand("ls -la"), "ls -la")
    }

    func testOddQuotingIsShownAsItIs() {
        let odd = "/bin/zsh -lc 'echo a' 'b'"
        XCTAssertEqual(T3Wire.unwrappedCommand(odd), odd)
    }

    func testSummariesAreAlwaysWords() {
        XCTAssertEqual(T3Wire.approvalSummary(kind: .command, item: nil), "Run a command")
        XCTAssertEqual(T3Wire.approvalSummary(kind: .fileChange, item: nil), "Change some files")
        XCTAssertEqual(T3Wire.approvalSummary(kind: .fileRead, item: nil), "Read a file")
        XCTAssertEqual(T3Wire.approvalSummary(kind: .permission, item: nil), "Get more permissions")
        XCTAssertEqual(T3Wire.approvalSummary(kind: .mcpElicitation, item: nil), "A tool has a question")
    }

    func testLongSummariesAreMarkedAsCutShort() throws {
        let json = #"{"id":"i","type":"approval_request","status":"running","prompt":"\#(String(repeating: "x", count: 1000))"}"#
        let item = try T3Wire.decoder().decode(T3Wire.TurnItem.self, from: Data(json.utf8))
        let summary = T3Wire.approvalSummary(kind: .command, item: item)
        XCTAssertLessThan(summary.count, 500)
        XCTAssertTrue(summary.hasSuffix("…"))
    }
}
