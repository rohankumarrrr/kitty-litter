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
        let selection = T3Wire.ModelSelection(ModelChoice(provider: "codex", model: "gpt-6.1-sol", effort: "medium"))
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

    // Kittens only believe a correction T3 shows as the user's.
    func testMessagesGoOutAsTheUser() throws {
        let message = T3Wire.DispatchMessage(commandId: "c", threadId: "t", messageId: "m", text: "hi", attachments: [], modelSelection: nil)
        XCTAssertEqual(try decoded(T3Wire.encode(message))["createdBy"] as? String, "user")

        let launch = T3Wire.LaunchThread(
            commandId: "c",
            threadId: "t",
            projectId: "p",
            title: "Title",
            generateTitle: false,
            modelSelection: .init(.frontier),
            runtimeMode: RuntimeMode.approvalRequired.rawValue,
            initialMessage: .init(messageId: "m", text: "hi", attachments: [])
        )
        let json = try decoded(T3Wire.encode(launch))
        XCTAssertNil(json["createdBy"], "T3 records the user when a launch doesn't say")
        XCTAssertNil(try XCTUnwrap(json["initialMessage"] as? [String: Any])["createdBy"])
    }

    func testRespondCommand() throws {
        let command = T3Wire.RespondToRequest(commandId: "c", threadId: "t", requestId: "r", decision: ApprovalDecision.acceptForSession.rawValue)
        let json = try decoded(T3Wire.encode(command)) as? [String: String]
        XCTAssertEqual(json, ["type": "runtime-request.respond", "commandId": "c", "threadId": "t", "requestId": "r", "decision": "acceptForSession"])
    }

    func testAnAnswerIsFiledUnderEachQuestionAndSendsNoDecision() throws {
        let command = T3Wire.RespondToRequest(commandId: "c", threadId: "t", requestId: "r", answers: ["plan": .one("Starter"), "extras": .several(["Support"])])
        let json = try decoded(T3Wire.encode(command))
        XCTAssertEqual(json["type"] as? String, "runtime-request.respond")
        XCTAssertEqual(json["answers"] as? NSDictionary, ["plan": "Starter", "extras": ["Support"]])
        XCTAssertNil(json["decision"])
    }

    // MARK: IDs and links

    func testApprovalItemIDMatchesWhatTheServerBuilds() {
        XCTAssertEqual(T3Wire.approvalItemID(requestID: T3Fixtures.approvalRequestID), T3Fixtures.approvalItemID)
    }

    private func turnItem(_ json: String) throws -> T3Wire.TurnItem {
        try T3Wire.decoder().decode(T3Wire.TurnItem.self, from: Data(json.utf8))
    }

    func testTheFinalReportIsTheLastThingTheAgentItselfSaid() throws {
        let items = try [
            #"{"id":"a","type":"assistant_message","status":"completed","runId":"r","startedAt":"2026-11-05T04:00:00.000Z","text":"Looking into it."}"#,
            #"{"id":"sub","type":"assistant_message","status":"completed","runId":"r","parentItemId":"x","startedAt":"2026-11-05T04:00:05.000Z","text":"A subagent talking."}"#,
            #"{"id":"b","type":"assistant_message","status":"completed","runId":"r","startedAt":"2026-11-05T04:00:03.000Z","text":"It's fixed."}"#,
            #"{"id":"msg:thinking:1","type":"assistant_message","status":"completed","runId":"r","startedAt":"2026-11-05T04:00:04.000Z","text":"Hmm, let me think."}"#,
            #"{"id":"c","type":"command_execution","status":"completed","runId":"r","startedAt":"2026-11-05T04:00:06.000Z"}"#,
        ].map(turnItem)
        XCTAssertEqual(T3Wire.finalReport(in: items), "It's fixed.")
        XCTAssertNil(T3Wire.finalReport(in: []))
    }

    func testAFinalReportLeadsWithTheErrorItEndedOn() throws {
        let items = try [
            #"{"id":"old","type":"error","status":"failed","runId":"r1","startedAt":"2026-11-05T04:00:00.000Z","failure":{"message":"An old problem"}}"#,
            #"{"id":"a","type":"assistant_message","status":"completed","runId":"r2","startedAt":"2026-11-05T04:01:00.000Z","text":"Trying that."}"#,
            #"{"id":"e","type":"error","status":"failed","runId":"r2","startedAt":"2026-11-05T04:01:05.000Z","failure":{"message":"Ran out of quota"}}"#,
        ].map(turnItem)
        XCTAssertEqual(T3Wire.finalReport(in: items), "Error: Ran out of quota\n\nTrying that.")
    }

    func testAskingForARunOnlyGetsWhatThatRunSaid() throws {
        let items = try [
            #"{"id":"a","type":"assistant_message","status":"completed","runId":"r1","startedAt":"2026-11-05T04:00:00.000Z","text":"It's live."}"#,
            #"{"id":"c","type":"command_execution","status":"completed","runId":"r2","startedAt":"2026-11-05T05:00:00.000Z"}"#,
        ].map(turnItem)
        XCTAssertEqual(T3Wire.finalReport(in: items), "It's live.")
        XCTAssertEqual(T3Wire.finalReport(in: items, run: "r1"), "It's live.")
        XCTAssertNil(T3Wire.finalReport(in: items, run: "r2"))
    }

    func testAQuestionsWordsAndOptionsAreRead() throws {
        let item = try turnItem(#"{"id":"q","type":"user_input_request","status":"running","requestId":"r","questions":[{"id":"1","header":"Pick","question":"Which one?","options":[{"label":"A","description":"First"},{"label":"B","description":"Second"}]},{"id":"2","header":"More","question":"And?","options":[]}]}"#)
        XCTAssertEqual(item.questions?.first?.question, "Which one?")
        XCTAssertEqual(item.questions?.first?.options?.map(\.label), ["A", "B"])
        XCTAssertEqual(item.questions?.count, 2)
    }

    func testEveryQuestionInARequestCanBeAnsweredFromShades() throws {
        let item = try turnItem(#"{"id":"q","type":"user_input_request","status":"running","requestId":"r","questions":[{"id":"plan","header":"Pick","question":"Which plan?","options":[{"label":"Starter","description":"","value":"starter-v2"},{"label":"Basic","description":""}]},{"id":"extras","header":"More","question":"Which extras?","options":[{"label":"Support","description":""},{"label":"Backups","description":""}],"multiSelect":true}]}"#)
        let form = try XCTUnwrap(T3Wire.answerForm(item.questions))
        XCTAssertEqual(form.parts, [
            AnswerForm.Part(key: "plan", text: "Which plan?", options: ["Starter", "Basic"], values: ["starter-v2", "Basic"], takesOwnWords: true),
            AnswerForm.Part(key: "extras", text: "Which extras?", options: ["Support", "Backups"], values: ["Support", "Backups"], takesOwnWords: true, picksSeveral: true),
        ], "an option sends its value, or its label without one")
        XCTAssertEqual(T3Wire.answers([["starter-v2"], ["Support"]], to: form), ["plan": .one("starter-v2"), "extras": .several(["Support"])], "a choice for a question that takes several goes as a list")
        XCTAssertEqual(T3Wire.answers([["Basic"], ["Support", "Backups"]], to: form), ["plan": .one("Basic"), "extras": .several(["Support", "Backups"])], "and so do several")
        XCTAssertEqual(T3Wire.answers([["My own words"], ["Something else"]], to: form), ["plan": .one("My own words"), "extras": .one("Something else")])
        XCTAssertNil(T3Wire.answers([["starter-v2"]], to: form), "every part needs an answer")
        XCTAssertNil(T3Wire.answers([["starter-v2", "Basic"], ["Support"]], to: form), "one choice where it takes one")
        XCTAssertNil(T3Wire.answers([["starter-v2"], []], to: form))
    }

    func testAQuestionWithNoIDCanOnlyBeAnsweredInT3() throws {
        let unnamed = try turnItem(#"{"id":"q","type":"user_input_request","status":"running","requestId":"r","questions":[{"id":"1","header":"A","question":"One?","options":[]},{"header":"A","question":"Which?","options":[]}]}"#)
        XCTAssertNil(T3Wire.answerForm(unnamed.questions), "with no ID there's nothing to file an answer under")
        XCTAssertNil(T3Wire.answerForm([]))
    }

    func testSearchAsksForOnlyTheKeysEveryServerTakesAndReadsOnlyWhichThreads() throws {
        let payload = try decoded(T3Wire.encode(T3Wire.SearchThreads(query: "coupon box")))
        XCTAssertEqual(payload as NSDictionary, ["query": "coupon box", "limit": 50], "newer keys would be turned away by older servers")
        let json = #"{"matches":[{"threadId":"t1","projectId":"p","source":"user","snippet":"<screen>coupon</screen>","messageCreatedAt":null,"quality":1},{"threadId":"t2","projectId":"p","source":"assistant","snippet":"the coupon box","messageCreatedAt":"2026-11-08T10:00:00.000Z","messageId":"m"}],"threads":[]}"#
        let result = try T3Wire.decoder().decode(T3Wire.SearchResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.matches.map(\.threadId), ["t1", "t2"])
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

    /// T3 lists only its older scopes under `scopes`, so a check of those alone would sign in again on every launch.
    func testSessionNeedsEveryScopeAsT3ListsThem() throws {
        func state(_ json: String) throws -> T3Wire.SessionState {
            try T3Wire.decoder().decode(T3Wire.SessionState.self, from: Data(json.utf8))
        }
        let issued = #"{"authenticated":true,"scopes":["orchestration:read","orchestration:operate"],"permissions":["orchestration:read","orchestration:operate","filesystem:read"]}"#
        XCTAssertTrue(try state(issued).isUsable)
        XCTAssertFalse(try state(#"{"authenticated":true,"scopes":["orchestration:read","orchestration:operate"],"permissions":["orchestration:read","orchestration:operate"]}"#).isUsable, "one from before pictures in folders signs in again")
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

    private func projection(createdBy: String?, messages: String) throws -> T3Wire.Projection {
        let by = createdBy.map { #""createdBy":"\#($0)","# } ?? ""
        let json = #"{"thread":{\#(by)"title":"T","projectId":"p"},"runs":[],"turnItems":[],"messages":\#(messages)}"#
        return try T3Wire.decoder().decode(T3Wire.Projection.self, from: Data(json.utf8))
    }

    func testAThreadAPersonStartedSaysSo() throws {
        XCTAssertEqual(try projection(createdBy: "user", messages: "[]").startedBy, .person)
    }

    func testAThreadAnAgentStartedNamesTheThreadOfItsFirstMessage() throws {
        let messages = #"[{"role":"assistant","createdAt":"2026-01-01T00:00:00Z"},{"role":"user","createdAt":"2026-01-03T00:00:00Z","senderThreadId":"later"},{"role":"user","createdAt":"2026-01-02T00:00:00Z","senderThreadId":"first"}]"#
        XCTAssertEqual(try projection(createdBy: "agent", messages: messages).startedBy, .thread("first"))
    }

    func testAnAgentsThreadWithNoSenderCantBeTraced() throws {
        XCTAssertEqual(try projection(createdBy: "agent", messages: #"[{"role":"user"}]"#).startedBy, .unknown)
        XCTAssertEqual(try projection(createdBy: nil, messages: "[]").startedBy, .unknown)
    }
}

extension T3WireTests {
    func testQuestionsSharingAnIDTakeOneAnswerInYourOwnWords() throws {
        let item = try turnItem(#"{"id":"q","type":"user_input_request","status":"running","requestId":"r","questions":[{"id":"choice","header":"A","question":"Which colour?","options":[{"label":"Red","description":""}],"allowCustomAnswer":false},{"id":"size","header":"S","question":"How many?","options":[]},{"id":"choice","header":"B","question":"Which size?","options":[{"label":"Large","description":""}]}]}"#)
        let form = try XCTUnwrap(T3Wire.answerForm(item.questions), "T3 files one answer under the ID they share")
        XCTAssertEqual(form.parts, [
            AnswerForm.Part(key: "choice", text: "Which colour?\nWhich size?", options: [], values: [], takesOwnWords: true),
            AnswerForm.Part(key: "size", text: "How many?", options: [], values: [], takesOwnWords: true),
        ], "no option answers both, so it's your words")
        XCTAssertEqual(T3Wire.answers([["Red, and large"], ["Two"]], to: form), ["choice": .one("Red, and large"), "size": .one("Two")])
        XCTAssertNil(T3Wire.answers([["Red"]], to: form), "every part still needs an answer")

        let twice = try turnItem(#"{"id":"q","type":"user_input_request","status":"running","requestId":"r","questions":[{"id":"Which colour?","header":"A","question":"Which colour?","options":[{"label":"Red","description":""}]},{"id":"Which colour?","header":"A","question":"Which colour?","options":[{"label":"Red","description":""}]}]}"#)
        XCTAssertEqual(T3Wire.answerForm(twice.questions)?.parts, [
            AnswerForm.Part(key: "Which colour?", text: "Which colour?", options: ["Red"], values: ["Red"], takesOwnWords: true),
        ], "the same question twice, as Claude's IDs are their words, is asked once")
    }
}
