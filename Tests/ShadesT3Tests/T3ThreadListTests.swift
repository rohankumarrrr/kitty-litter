import ShadesCore
@testable import ShadesT3
import XCTest

final class T3ThreadListTests: XCTestCase {
    private func thread(
        id: String,
        title: String? = nil,
        project: String = "project-1",
        status: String = "running",
        updatedAt: String = "2026-11-05T04:00:00.000Z",
        pending: String = "null",
        parent: String? = nil,
        relationship: String? = nil,
        archivedAt: String? = nil
    ) -> String {
        T3Fixtures.threadTemplate
            .replacingOccurrences(of: "__ID__", with: id)
            .replacingOccurrences(of: "__PROJECT__", with: project)
            .replacingOccurrences(of: "__TITLE__", with: title ?? "Thread \(id)")
            .replacingOccurrences(of: "__STATUS__", with: status)
            .replacingOccurrences(of: "__UPDATED__", with: updatedAt)
            .replacingOccurrences(of: #""__PENDING__""#, with: pending)
            .replacingOccurrences(of: #""__PARENT__""#, with: parent.map { #""\#($0)""# } ?? "null")
            .replacingOccurrences(of: #""__RELATIONSHIP__""#, with: relationship.map { #""\#($0)""# } ?? "null")
            .replacingOccurrences(of: #""__ARCHIVED__""#, with: archivedAt.map { #""\#($0)""# } ?? "null")
    }

    private func project(id: String = "project-1", title: String = "Shades", root: String = "/code/shades") -> String {
        T3Fixtures.projectTemplate
            .replacingOccurrences(of: "__ID__", with: id)
            .replacingOccurrences(of: "__TITLE__", with: title)
            .replacingOccurrences(of: "__ROOT__", with: root)
    }

    func testALastRunIsReadWhenThereIsOneAndNotNeededWhenThereIsnt() throws {
        let withRun = thread(id: "ran", status: "completed")
            .replacingOccurrences(of: #""latestRunId":null"#, with: #""latestRunId":"run-3""#)
        let withoutFields = thread(id: "old", status: "completed")
            .replacingOccurrences(of: #""latestRunId":null,"#, with: "")
            .replacingOccurrences(of: #""latestRunCompletedAt":"2026-11-02T19:11:15.374Z","#, with: "")
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [withRun, withoutFields]))
        let listed = list.agentThreads(summaries: [:])

        let ran = try XCTUnwrap(listed.first { $0.id == "ran" })
        XCTAssertEqual(ran.lastRunID, "run-3")
        XCTAssertEqual(ran.lastRunEndedAt, T3Wire.parseDate("2026-11-02T19:11:15.374Z"))
        let old = try XCTUnwrap(listed.first { $0.id == "old" })
        XCTAssertNil(old.lastRunID)
        XCTAssertNil(old.lastRunEndedAt)
    }

    func testAThreadWaitingOnASubagentIsStillWorking() throws {
        var list = T3ThreadList()
        let parent = thread(id: "parent", status: "completed")
        list.apply(try snapshot(threads: [parent, thread(id: "reviewer", status: "running", parent: "parent", relationship: "subagent")]))
        let listed = list.agentThreads(summaries: [:])
        XCTAssertEqual(listed.map(\.id), ["parent"], "a reviewer never shows up by itself")
        XCTAssertEqual(listed.first?.status, .running)

        list.apply(try updated(thread(id: "reviewer", status: "completed", parent: "parent", relationship: "subagent")))
        XCTAssertEqual(list.agentThreads(summaries: [:]).first?.status, .completed)
    }

    func testAThreadWithSomethingLeftRunningIsStillWorking() throws {
        var list = T3ThreadList()
        let running = thread(id: "t", status: "completed")
            .replacingOccurrences(of: #""pendingBackgroundTasks":[]"#, with: #""pendingBackgroundTasks":[{"id":"task-1"}]"#)
        XCTAssertTrue(running.contains("task-1"))
        list.apply(try snapshot(threads: [running]))
        XCTAssertEqual(list.agentThreads(summaries: [:]).first?.status, .running)
    }

    func testAQuestionGoesOnTheThreadOnceItsWordsAreKnown() throws {
        var list = T3ThreadList()
        let pending = #"{"id":"req-1","kind":"user_input","createdAt":"2026-11-05T04:00:00.000Z","blocking":true}"#
        list.apply(try snapshot(threads: [thread(id: "t", title: "Work", pending: pending)]))

        XCTAssertEqual(list.pendingQuestions, [T3ThreadList.PendingQuestion(requestID: "req-1", threadID: "t")])
        XCTAssertTrue(list.pendingApprovals.isEmpty)
        let waiting = list.agentThreads(summaries: [:])
        XCTAssertEqual(waiting.first?.status, .waitingForAnswer)
        XCTAssertNil(waiting.first?.pendingQuestion)

        let words = T3ThreadList.QuestionWords(text: "Which?", options: ["A", "B"], moreCount: 0)
        let asked = list.agentThreads(summaries: [:], questions: ["req-1": words])
        let askedAt = ISO8601DateFormatter().date(from: "2026-11-05T04:00:00Z")
        XCTAssertEqual(asked.first?.pendingQuestion, AgentQuestion(id: "req-1", threadID: "t", threadTitle: "Work", text: "Which?", options: ["A", "B"], askedAt: askedAt))
    }

    private func item(_ json: String) throws -> T3Wire.ShellItem {
        try T3Wire.decoder().decode(T3Wire.ShellItem.self, from: Data(json.utf8))
    }

    private func snapshot(threads: [String], projects: [String]? = nil, extra: String = "") throws -> T3Wire.ShellItem {
        let projects = (projects ?? [project()]).joined(separator: ",")
        return try item(#"{"kind":"snapshot","snapshot":{"schemaVersion":2,"snapshotSequence":1,"threads":[\#(threads.joined(separator: ","))],"archivedThreads":[],"projects":[\#(projects)]}\#(extra)}"#)
    }

    private func updated(_ thread: String, location: String = "active") throws -> T3Wire.ShellItem {
        try item(#"{"kind":"thread.updated","sequence":2,"location":"\#(location)","thread":\#(thread)}"#)
    }

    private let pendingCommand = #"{"id":"request-1","kind":"command","createdAt":"2026-11-05T04:01:00.000Z","blocking":true}"#

    func testThreadsAreListedNewestFirstWithTheirDetails() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [
            thread(id: "old", updatedAt: "2026-11-05T01:00:00.000Z"),
            thread(id: "new", updatedAt: "2026-11-05T02:00:00.000Z"),
        ]))
        let threads = list.agentThreads(summaries: [:])
        XCTAssertEqual(threads.map(\.id), ["new", "old"])
        XCTAssertEqual(threads[0].title, "Thread new")
        XCTAssertEqual(threads[0].projectTitle, "Shades")
        XCTAssertEqual(threads[0].model, "claude-opus-5-5")
        XCTAssertEqual(threads[0].status, .running)
    }

    func testStatusesMapToTheContract() throws {
        let expected: [(String, AgentStatus)] = [
            ("idle", .idle),
            ("preparing", .starting),
            ("queued", .starting),
            ("starting", .starting),
            ("running", .running),
            ("waiting", .running),
            ("completed", .completed),
            ("failed", .failed),
            ("interrupted", .interrupted),
            ("cancelled", .interrupted),
            ("rolled_back", .interrupted),
            ("from_the_future", .idle),
        ]
        for (wire, status) in expected {
            var list = T3ThreadList()
            list.apply(try snapshot(threads: [thread(id: "t", status: wire)]))
            XCTAssertEqual(list.agentThreads(summaries: [:]).first?.status, status, wire)
        }
    }

    /// The server follows its real snapshot with one that only refreshes projects and names no threads.
    func testProjectRefreshDoesNotEmptyTheList() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [thread(id: "t")]))
        list.apply(try snapshot(threads: [], projects: [project(title: "Renamed")], extra: #","resolvedRepositoryIdentityRoots":["/code/shades"]"#))
        XCTAssertEqual(list.agentThreads(summaries: [:]).map(\.projectTitle), ["Renamed"])
    }

    func testAProjectRefreshAloneDoesNotCountAsLoaded() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [], extra: #","resolvedRepositoryIdentityRoots":[]"#))
        XCTAssertFalse(list.isLoaded)
    }

    func testUpdatesAndRemovals() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [thread(id: "a"), thread(id: "b")]))
        list.apply(try updated(thread(id: "a", status: "completed", updatedAt: "2026-11-05T05:00:00.000Z")))
        XCTAssertEqual(list.agentThreads(summaries: [:]).first?.status, .completed)

        list.apply(try item(#"{"kind":"thread.removed","sequence":3,"location":"active","threadId":"b"}"#))
        XCTAssertEqual(list.agentThreads(summaries: [:]).map(\.id), ["a"])

        list.apply(try updated(thread(id: "a"), location: "archive"))
        XCTAssertEqual(list.agentThreads(summaries: [:]), [])
    }

    func testArchivedAndSubagentThreadsAreNotListed() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [
            thread(id: "shown"),
            thread(id: "archived", archivedAt: "2026-11-05T03:00:00.000Z"),
            thread(id: "child", parent: "shown", relationship: "subagent"),
            thread(id: "fork", parent: "shown", relationship: "fork"),
        ]))
        XCTAssertEqual(Set(list.agentThreads(summaries: [:]).map(\.id)), ["shown", "fork"])
    }

    func testNoProjectThreadsHaveNoProjectTitle() throws {
        var list = T3ThreadList(scratchRoot: "/home/.t3/scratch")
        list.apply(try snapshot(
            threads: [thread(id: "t", project: "scratch")],
            projects: [project(id: "scratch", title: "No project", root: "/home/.t3/scratch/"), project()]
        ))
        XCTAssertNil(list.agentThreads(summaries: [:]).first?.projectTitle)
        XCTAssertEqual(list.projects.map(\.title), ["Shades"])
    }

    func testProjectUpdates() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: []))
        list.apply(try item(#"{"kind":"project.updated","sequence":2,"project":\#(project(id: "two", title: "Another"))}"#))
        XCTAssertEqual(list.projects.map(\.title), ["Another", "Shades"])
        list.apply(try item(#"{"kind":"project.removed","sequence":3,"projectId":"two"}"#))
        XCTAssertEqual(list.projects.map(\.title), ["Shades"])
    }

    // MARK: Approvals

    func testPendingApprovalShowsOnceItsWordsAreKnown() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [thread(id: "t", status: "waiting", pending: pendingCommand)]))
        XCTAssertEqual(list.pendingApprovals, [.init(requestID: "request-1", threadID: "t", kind: .command)])

        // Waiting for approval as soon as the server says so, even before the words arrive.
        var thread = try XCTUnwrap(list.agentThreads(summaries: [:]).first)
        XCTAssertEqual(thread.status, .waitingForApproval)
        XCTAssertEqual(thread.pendingApprovals, [])

        thread = try XCTUnwrap(list.agentThreads(summaries: ["request-1": "Run: echo hi"]).first)
        XCTAssertEqual(thread.status, .waitingForApproval)
        let request = try XCTUnwrap(thread.pendingApprovals.first)
        XCTAssertEqual(request.id, "request-1")
        XCTAssertEqual(request.threadID, "t")
        XCTAssertEqual(request.threadTitle, "Thread t")
        XCTAssertEqual(request.kind, .command)
        XCTAssertEqual(request.summary, "Run: echo hi")
    }

    func testAKindOfEachApprovalMaps() throws {
        let kinds: [(String, ApprovalKind)] = [
            ("command", .command),
            ("file-read", .fileRead),
            ("file-change", .fileChange),
            ("mcp-elicitation", .mcpElicitation),
            ("permission", .permission),
        ]
        for (wire, kind) in kinds {
            XCTAssertEqual(T3Wire.approvalKind(wire), kind)
        }
        XCTAssertNil(T3Wire.approvalKind("user_input"))
    }

    func testAQuestionIsWaitingForAnAnswerNotAnApproval() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [thread(id: "t", status: "waiting", pending: #"{"id":"q","kind":"user_input","createdAt":"2026-11-05T04:01:00.000Z","blocking":true}"#)]))
        XCTAssertEqual(list.pendingApprovals, [])
        XCTAssertEqual(list.agentThreads(summaries: [:]).first?.status, .waitingForAnswer)
    }

    func testAQuestionThatDoesntBlockLeavesTheThreadRunning() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [thread(id: "t", status: "running", pending: #"{"id":"q","kind":"user_input","createdAt":"2026-11-05T04:01:00.000Z","blocking":false}"#)]))
        XCTAssertEqual(list.agentThreads(summaries: [:]).first?.status, .running)
    }

    /// A subagent has no row of its own, so its approval surfaces on the thread you can see, but
    /// answering it still has to name the subagent's own thread.
    func testASubagentsApprovalSurfacesOnItsParent() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [
            thread(id: "parent", title: "The parent"),
            thread(id: "child", status: "waiting", pending: pendingCommand, parent: "parent", relationship: "subagent"),
        ]))
        let threads = list.agentThreads(summaries: ["request-1": "Run: ls"])
        XCTAssertEqual(threads.map(\.id), ["parent"])
        XCTAssertEqual(threads[0].status, .waitingForApproval)
        XCTAssertEqual(threads[0].pendingApprovals.first?.threadID, "child")
        XCTAssertEqual(threads[0].pendingApprovals.first?.threadTitle, "The parent")
    }

    func testRuntimeModeIsKnown() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [thread(id: "t")]))
        XCTAssertEqual(list.runtimeMode(of: "t"), "full-access")
        XCTAssertNil(list.runtimeMode(of: "unknown"))
    }

    // MARK: Everything, for reading who said what

    func testAskingForEverythingLeavesTheDefaultsAlone() throws {
        let everything = try JSONSerialization.jsonObject(with: T3Wire.encode(T3Wire.SubscribeShell.everything)) as? [String: Bool]
        XCTAssertEqual(everything, ["requestCompletionMarker": true, "omitIdleSubagents": false, "omitOlderSettled": false])
        let live = try JSONSerialization.jsonObject(with: T3Wire.encode(T3Wire.SubscribeShell())) as? [String: Bool]
        XCTAssertEqual(live, ["requestCompletionMarker": true, "omitIdleSubagents": true, "omitOlderSettled": true])
    }

    func testAskingForAWholeThreadTurnsOffTheWindow() throws {
        let whole = try JSONSerialization.jsonObject(with: T3Wire.encode(T3Wire.SubscribeThread.whole(threadID: "t"))) as? [String: Any]
        XCTAssertEqual(whole?["threadId"] as? String, "t")
        XCTAssertEqual(whole?["acceptBoundedSnapshot"] as? Bool, false)
        XCTAssertNil(whole?["afterSequence"], "or it would replay events instead")
    }

    func testASubagentIsKnownByTheThreadAPersonCanSee() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [
            thread(id: "parent", title: "The parent"),
            thread(id: "child", parent: "parent", relationship: "subagent"),
            thread(id: "grandchild", parent: "child", relationship: "subagent"),
            thread(id: "orphan", parent: "archived", relationship: "subagent"),
        ]))
        XCTAssertEqual(list.listedThreadID(of: "parent"), "parent")
        XCTAssertEqual(list.listedThreadID(of: "grandchild"), "parent")
        XCTAssertNil(list.listedThreadID(of: "orphan"), "its parent was archived, so T3 can't say")
        XCTAssertNil(list.listedThreadID(of: "unknown"))
    }

    func testASubagentWaitingOnYouShowsOnTheThreadAbove() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [
            thread(id: "asks", title: "Asks"),
            thread(id: "asks-child", pending: #"{"id":"q","kind":"user_input","createdAt":"2026-11-05T04:00:00.000Z","blocking":true}"#, parent: "asks", relationship: "subagent"),
            thread(id: "approves", title: "Approves"),
            thread(id: "approves-child", pending: #"{"id":"a","kind":"command","createdAt":"2026-11-05T04:00:00.000Z","blocking":true}"#, parent: "approves", relationship: "subagent"),
            thread(id: "quiet", title: "Quiet"),
        ]))
        let listed = Dictionary(uniqueKeysWithValues: list.threadsWithoutWords.map { ($0.id, $0) })
        XCTAssertNotNil(listed["asks"]?.pendingQuestion)
        XCTAssertEqual(listed["approves"]?.status, .waitingForApproval)
        XCTAssertNil(listed["quiet"]?.pendingQuestion)
    }

    func testSettledAndPullRequestsComeThrough() throws {
        let open = thread(id: "open")
            .replacingOccurrences(of: #""settledAt":"2026-11-02T19:16:42.734Z""#, with: #""settledAt":null"#)
            .replacingOccurrences(of: #""pullRequests":[]"#, with: #""pullRequests":[{"number":7,"url":"https://example.com/7","snapshot":{"state":"merged","title":"First"}},{"number":12,"url":"https://example.com/12","snapshot":{"state":"open","title":"Second"}},{"number":99}]"#)
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [open, thread(id: "settled")]))
        let threads = Dictionary(uniqueKeysWithValues: list.agentThreads(summaries: [:]).map { ($0.id, $0) })
        XCTAssertEqual(threads["open"]?.isSettled, false)
        XCTAssertEqual(threads["open"]?.pullRequest, ThreadPullRequest(number: 12, state: "open", url: "https://example.com/12"), "the last one it can read")
        XCTAssertEqual(threads["settled"]?.isSettled, true)
        XCTAssertNil(threads["settled"]?.pullRequest)
    }

    func testABadThreadDoesNotLoseTheRest() throws {
        var list = T3ThreadList()
        list.apply(try snapshot(threads: [#"{"id":"broken"}"#, thread(id: "fine")]))
        XCTAssertEqual(list.agentThreads(summaries: [:]).map(\.id), ["fine"])
    }
}
