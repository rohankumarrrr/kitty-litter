import ShadesCore
@testable import ShadesT3
import XCTest

final class T3TurnTrackerTests: XCTestCase {
    private func items(_ frames: [String]) throws -> [T3Wire.ThreadItem] {
        try frames.flatMap { frame in
            try T3Wire.frames(T3Wire.ChunkFrame<T3Wire.ThreadItem>.self, in: Data(frame.utf8)).flatMap(\.items)
        }
    }

    private func streamedTracker() -> T3TurnTracker {
        T3TurnTracker(threadID: T3Fixtures.streamedTurnThreadID, messageID: T3Fixtures.streamedTurnMessageID, threadTitle: "A story")
    }

    private func run(_ tracker: inout T3TurnTracker, _ items: [T3Wire.ThreadItem]) -> [AgentReplyEvent] {
        items.flatMap { tracker.apply($0) }
    }

    private func text(of events: [AgentReplyEvent]) -> String {
        events.reduce(into: "") { result, event in
            if case let .text(delta) = event { result += delta }
        }
    }

    func testRecordedTurnStreamsDeltasThatAddUpToTheFullText() throws {
        var tracker = streamedTracker()
        let events = run(&tracker, try items(T3Fixtures.streamedTurn))

        let deltas = events.filter { if case .text = $0 { return true } else { return false } }
        XCTAssertGreaterThan(deltas.count, 5, "This recording streamed, so there should be many deltas")

        guard case let .finished(fullText) = events.last else { return XCTFail("Should end by finishing") }
        XCTAssertTrue(fullText.hasPrefix("Every morning, Miso"))
        XCTAssertEqual(text(of: events), fullText)
        XCTAssertTrue(tracker.isFinished)
    }

    func testNothingFollowsTheEnd() throws {
        var tracker = streamedTracker()
        let recorded = try items(T3Fixtures.streamedTurn)
        _ = run(&tracker, recorded)
        XCTAssertEqual(run(&tracker, recorded), [])
    }

    /// After a reconnect the server can send updates again. Whole-text updates make that harmless.
    func testReplayedUpdatesDontRepeatText() throws {
        var tracker = streamedTracker()
        let recorded = try items(T3Fixtures.streamedTurn)
        let middle = recorded.count / 2
        var events = run(&tracker, Array(recorded[..<middle]))
        events += run(&tracker, Array(recorded[..<middle]))
        events += run(&tracker, Array(recorded[middle...]))

        guard case let .finished(fullText) = events.last else { return XCTFail("Should end by finishing") }
        XCTAssertEqual(text(of: events), fullText)
    }

    func testOtherRunsAreIgnored() throws {
        var tracker = T3TurnTracker(threadID: T3Fixtures.streamedTurnThreadID, messageID: "someone-elses-message", threadTitle: "A story")
        XCTAssertEqual(run(&tracker, try items(T3Fixtures.streamedTurn)), [])
        XCTAssertNil(tracker.runID)
    }

    func testLaunchResultNamesTheRun() throws {
        let frames = try T3Wire.frames(T3Wire.ExitFrame<T3Wire.LaunchResult>.self, in: Data(T3Fixtures.launchExit.utf8))
        let result = try XCTUnwrap(frames.first?.exit?.value)
        XCTAssertEqual(result.threadId, T3Fixtures.streamedTurnThreadID)
        XCTAssertNotNil(result.sequence)
        let run = result.projection.runs.compactMap(\.value).first { $0.userMessageId == T3Fixtures.streamedTurnMessageID }
        XCTAssertNotNil(run)
    }

    // MARK: Approvals

    func testRecordedApprovalShowsTheActualCommandOnce() throws {
        var tracker = T3TurnTracker(threadID: T3Fixtures.approvalTurnThreadID, messageID: T3Fixtures.approvalTurnMessageID, threadTitle: "Approval")
        let recorded = try items(T3Fixtures.approvalTurn)
        let events = run(&tracker, recorded) + run(&tracker, recorded)

        let requests = events.compactMap { event -> ApprovalRequest? in
            if case let .needsApproval(request) = event { return request }
            return nil
        }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.id, T3Fixtures.approvalRequestID)
        XCTAssertEqual(requests.first?.threadID, T3Fixtures.approvalTurnThreadID)
        XCTAssertEqual(requests.first?.threadTitle, "Approval")
        XCTAssertEqual(requests.first?.kind, .command)
        XCTAssertEqual(requests.first?.summary, "Run: echo shades-approval-test > /tmp/shades-approval-test.txt")
    }

    func testAnApprovalAlreadyAnsweredIsNotAsked() throws {
        var tracker = T3TurnTracker(threadID: T3Fixtures.approvalTurnThreadID, messageID: T3Fixtures.approvalTurnMessageID, threadTitle: "Approval")
        // The recording without the frame where the request was still open.
        var recorded = T3Fixtures.approvalTurn
        recorded.remove(at: 2)
        let events = run(&tracker, try items(recorded))
        XCTAssertFalse(events.contains { if case .needsApproval = $0 { return true } else { return false } })
    }

    // MARK: How turns end

    private func event(_ type: String, _ payload: String, sequence: Int = 1) throws -> T3Wire.ThreadItem {
        let json = #"{"kind":"event","sequence":\#(sequence),"event":{"type":"\#(type)","payload":\#(payload)}}"#
        return try T3Wire.decoder().decode(T3Wire.ThreadItem.self, from: Data(json.utf8))
    }

    private func runUpdate(_ status: String) throws -> T3Wire.ThreadItem {
        try event("run.updated", #"{"id":"run-1","userMessageId":"message-1","status":"\#(status)"}"#)
    }

    private func newTracker() -> T3TurnTracker {
        T3TurnTracker(threadID: "thread-1", messageID: "message-1", threadTitle: "Thread")
    }

    func testFailedRunReportsTheLastError() throws {
        var tracker = newTracker()
        var events = tracker.apply(try runUpdate("running"))
        events += tracker.apply(try event("turn-item.updated", #"{"id":"e","type":"error","status":"failed","runId":"run-1","failure":{"class":"provider_error","message":"Out of credits","code":null,"retryable":false}}"#))
        events += tracker.apply(try runUpdate("failed"))
        XCTAssertEqual(events, [.failed(message: "Out of credits")])
    }

    func testStoppedRunsFail() throws {
        for status in ["interrupted", "cancelled", "rolled_back"] {
            var tracker = newTracker()
            XCTAssertEqual(tracker.apply(try runUpdate(status)), [.failed(message: "The agent was stopped.")], status)
            XCTAssertTrue(tracker.isFinished)
        }
    }

    func testWaitingIsNotTheEnd() throws {
        var tracker = newTracker()
        XCTAssertEqual(tracker.apply(try runUpdate("waiting")), [])
        XCTAssertFalse(tracker.isFinished)
    }

    func testSeveralMessagesJoinWithABlankLine() throws {
        var tracker = newTracker()
        func message(_ id: String, _ text: String) throws -> T3Wire.ThreadItem {
            try event("turn-item.updated", #"{"id":"item-\#(id)","type":"assistant_message","status":"completed","runId":"run-1","parentItemId":null,"messageId":"\#(id)","text":"\#(text)","streaming":false}"#)
        }
        var events = tracker.apply(try runUpdate("running"))
        events += tracker.apply(try message("a", "First."))
        events += tracker.apply(try message("b", "Second."))
        events += tracker.apply(try runUpdate("completed"))
        XCTAssertEqual(events, [.text(delta: "First."), .text(delta: "\n\nSecond."), .finished(fullText: "First.\n\nSecond.")])
    }

    func testASubagentsWordsAreNotTheReply() throws {
        var tracker = newTracker()
        var events = tracker.apply(try runUpdate("running"))
        events += tracker.apply(try event("turn-item.updated", #"{"id":"i","type":"assistant_message","status":"completed","runId":"run-1","parentItemId":"parent","messageId":"m","text":"Inner thoughts","streaming":false}"#))
        XCTAssertEqual(events, [])
    }

    func testSnapshotPicksUpARunAlreadyGoing() throws {
        let json = #"""
        {"kind":"snapshot","snapshotSequence":9,"projection":{"thread":{"title":"Named by T3"},
        "runs":[{"id":"run-1","userMessageId":"message-1","status":"running"}],
        "turnItems":[{"id":"i","type":"assistant_message","status":"running","runId":"run-1","parentItemId":null,"messageId":"m","text":"So far","streaming":true}]}}
        """#
        var tracker = T3TurnTracker(threadID: "thread-1", messageID: "message-1", threadTitle: "")
        let events = tracker.apply(try T3Wire.decoder().decode(T3Wire.ThreadItem.self, from: Data(json.utf8)))
        XCTAssertEqual(events, [.text(delta: "So far")])
        XCTAssertEqual(tracker.threadTitle, "Named by T3")
        XCTAssertEqual(tracker.runID, "run-1")
    }

    /// A steer joins a run another message started, so following only the run its own message started never ended.
    func testASteerFollowsTheRunItJoinedToItsEnd() throws {
        var tracker = newTracker()
        func update(_ status: String) throws -> T3Wire.ThreadItem {
            try event("run.updated", #"{"id":"run-0","userMessageId":"message-0","status":"\#(status)"}"#)
        }
        var events = tracker.apply(try update("running"))
        events += tracker.apply(try event("turn-item.updated", #"{"id":"a0","type":"assistant_message","status":"completed","runId":"run-0","parentItemId":null,"messageId":"m0","text":"Drawing a logo.","streaming":false}"#))
        XCTAssertEqual(events, [], "the run's own words before the steer aren't its answer")
        events += tracker.apply(try event("turn-item.updated", #"{"id":"u1","type":"user_message","status":"completed","runId":"run-0","messageId":"message-1","text":"Make it blue"}"#))
        events += tracker.apply(try event("turn-item.updated", #"{"id":"a1","type":"assistant_message","status":"completed","runId":"run-0","parentItemId":null,"messageId":"m1","text":"A blue logo.","streaming":false}"#))
        events += tracker.apply(try update("completed"))
        XCTAssertEqual(events, [.text(delta: "A blue logo."), .finished(fullText: "A blue logo.")])
        XCTAssertEqual(tracker.runID, "run-0")
    }

    func testASnapshotPicksUpARunAlreadySteered() throws {
        let json = #"""
        {"kind":"snapshot","snapshotSequence":9,"projection":{"thread":{"title":"Logo"},
        "runs":[{"id":"run-0","userMessageId":"message-0","status":"completed"}],
        "turnItems":[{"id":"u1","type":"user_message","status":"completed","runId":"run-0","messageId":"message-1","text":"Make it blue"},
        {"id":"a1","type":"assistant_message","status":"completed","runId":"run-0","parentItemId":null,"messageId":"m1","text":"A blue logo.","streaming":false}]}}
        """#
        var tracker = newTracker()
        let events = tracker.apply(try T3Wire.decoder().decode(T3Wire.ThreadItem.self, from: Data(json.utf8)))
        XCTAssertEqual(events, [.text(delta: "A blue logo."), .finished(fullText: "A blue logo.")])
    }

    /// Queued words have no run until theirs starts, so they never take the one going for theirs.
    func testQueuedWordsWaitForTheirOwnRun() throws {
        var tracker = newTracker()
        var events = tracker.apply(try event("run.updated", #"{"id":"run-0","userMessageId":"message-0","status":"running"}"#))
        events += tracker.apply(try event("turn-item.updated", #"{"id":"u1","type":"user_message","status":"completed","runId":null,"messageId":"message-1","text":"Next, the footer"}"#))
        events += tracker.apply(try event("run.updated", #"{"id":"run-0","userMessageId":"message-0","status":"completed"}"#))
        XCTAssertEqual(events, [])
        XCTAssertFalse(tracker.isFinished)
        XCTAssertNil(tracker.runID)
    }

    func testARenameIsPickedUp() throws {
        var tracker = newTracker()
        _ = tracker.apply(try event("thread.metadata-updated", #"{"title":"A better title"}"#))
        XCTAssertEqual(tracker.threadTitle, "A better title")
    }
}
