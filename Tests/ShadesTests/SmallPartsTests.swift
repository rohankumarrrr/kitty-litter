import CoreGraphics
@testable import Shades
import ShadesCore
import XCTest

final class QuickSessionTests: XCTestCase {
    func testReusesTheThreadForAboutTenMinutes() {
        var session = QuickSession()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertNil(session.thread(at: start))
        session.use("a", at: start)
        XCTAssertEqual(session.thread(at: start.addingTimeInterval(9 * 60)), "a")
        XCTAssertNil(session.thread(at: start.addingTimeInterval(10 * 60 + 1)))
    }

    func testTheTimeRunsFromTheLastUse() {
        var session = QuickSession()
        let start = Date(timeIntervalSince1970: 1000)
        session.use("a", at: start)
        session.use("a", at: start.addingTimeInterval(9 * 60))
        XCTAssertEqual(session.thread(at: start.addingTimeInterval(18 * 60)), "a")
    }

    func testResetStartsFresh() {
        var session = QuickSession()
        let start = Date(timeIntervalSince1970: 1000)
        session.use("a", at: start)
        session.reset()
        XCTAssertNil(session.thread(at: start))
    }
}

final class ApprovalQueueTests: XCTestCase {
    private func request(_ id: String, at time: TimeInterval = 0, kind: ApprovalKind = .command) -> ApprovalRequest {
        ApprovalRequest(id: id, threadID: "t", threadTitle: "Thread", kind: kind, summary: "do \(id)", createdAt: Date(timeIntervalSince1970: time))
    }

    private func thread(_ pending: [ApprovalRequest]) -> AgentThread {
        AgentThread(id: "t", title: "Thread", projectTitle: nil, status: .waitingForApproval, model: "m", updatedAt: Date(), pendingApprovals: pending)
    }

    func testOldestFirstAndNoDuplicates() {
        var queue = ApprovalQueue()
        queue.add(request("b", at: 2))
        queue.add(request("a", at: 1))
        queue.add(request("a", at: 1))
        queue.sync(with: [thread([request("a", at: 1)])])
        XCTAssertEqual(queue.pending.map(\.id), ["a", "b"])
    }

    func testCountsThroughABatch() {
        var queue = ApprovalQueue()
        queue.add(request("a", at: 1))
        queue.add(request("b", at: 2))
        queue.add(request("c", at: 3))
        XCTAssertEqual(queue.position, 1)
        XCTAssertEqual(queue.total, 3)
        queue.answer("a")
        XCTAssertEqual(queue.position, 2)
        XCTAssertEqual(queue.total, 3)
        queue.answer("b")
        queue.answer("c")
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.position, 1)
    }

    func testAnAnswerCantBeBroughtBackByAStaleList() {
        var queue = ApprovalQueue()
        let a = request("a")
        queue.sync(with: [thread([a])])
        queue.answer("a")
        queue.sync(with: [thread([a])])
        XCTAssertTrue(queue.isEmpty)
    }

    func testAnsweredElsewhereGoesAway() {
        var queue = ApprovalQueue()
        queue.sync(with: [thread([request("a")])])
        XCTAssertFalse(queue.isEmpty)
        queue.sync(with: [thread([])])
        XCTAssertTrue(queue.isEmpty)
    }

    func testARequestFromAStreamSurvivesAListThatHasntCaughtUp() {
        var queue = ApprovalQueue()
        queue.add(request("a"))
        queue.sync(with: [thread([])])
        XCTAssertEqual(queue.pending.map(\.id), ["a"])
    }

    func testAFailedAnswerComesBack() {
        var queue = ApprovalQueue()
        let a = request("a")
        queue.add(a)
        queue.answer("a")
        queue.restore(a)
        XCTAssertEqual(queue.pending.map(\.id), ["a"])
    }

    func testSessionAllowOnlyWhereItMakesSense() {
        XCTAssertTrue(ApprovalPolicy.offersSessionAllow(.command))
        XCTAssertTrue(ApprovalPolicy.offersSessionAllow(.fileRead))
        XCTAssertTrue(ApprovalPolicy.offersSessionAllow(.fileChange))
        XCTAssertFalse(ApprovalPolicy.offersSessionAllow(.mcpElicitation))
        XCTAssertFalse(ApprovalPolicy.offersSessionAllow(.permission))
    }
}

final class AgentWatchTests: XCTestCase {
    private func thread(_ id: String, _ status: AgentStatus, ago: TimeInterval = 0, approvals: [ApprovalRequest] = []) -> AgentThread {
        AgentThread(id: id, title: id, projectTitle: nil, status: status, model: "m", updatedAt: Date().addingTimeInterval(-ago), pendingApprovals: approvals)
    }

    func testNoticesWorkFinishing() {
        var watch = AgentWatch()
        XCTAssertEqual(watch.update([thread("a", .running)]), [])
        XCTAssertTrue(watch.isBusy)
        let done = thread("a", .completed)
        XCTAssertEqual(watch.update([done]), [.finished(done)])
        XCTAssertFalse(watch.isBusy)
        XCTAssertEqual(watch.update([done]), [])
    }

    func testOldFinishedThreadsDontCelebrate() {
        var watch = AgentWatch()
        XCTAssertEqual(watch.update([thread("a", .completed)]), [])
    }

    func testAQuickQuestionIsntWork() {
        var watch = AgentWatch()
        watch.markQuick("q")
        XCTAssertEqual(watch.update([thread("q", .running)]), [])
        XCTAssertFalse(watch.isBusy)
        XCTAssertEqual(watch.update([thread("q", .completed)]), [])
    }

    func testFailuresAndQuestionsAreNoticed() {
        var watch = AgentWatch()
        _ = watch.update([thread("a", .running), thread("b", .running)])
        let failed = thread("a", .failed)
        var asking = thread("b", .waitingForAnswer)
        // The words arrive a moment after the thread stops, and then it counts, once.
        XCTAssertEqual(watch.update([failed, asking]), [.failed(failed)])
        let question = AgentQuestion(id: "q", threadID: "b", threadTitle: "b", text: "Which?")
        asking.pendingQuestion = question
        XCTAssertEqual(watch.update([failed, asking]), [.hasQuestion(question)])
        XCTAssertEqual(watch.update([failed, asking]), [])
    }

    func testRowsPutWhatNeedsYouFirstAndHideOldThreads() {
        var watch = AgentWatch()
        let request = ApprovalRequest(id: "r", threadID: "w", threadTitle: "w", kind: .command, summary: "s", createdAt: Date())
        _ = watch.update([
            thread("old", .completed, ago: 60 * 60),
            thread("idle", .idle),
            thread("recent", .completed, ago: 60),
            thread("run", .running),
            thread("wait", .running, approvals: [request]),
        ])
        XCTAssertEqual(watch.rows(at: Date()).map(\.id), ["wait", "run", "recent"])
    }

    func testSummaries() {
        var watch = AgentWatch()
        _ = watch.update([])
        XCTAssertEqual(watch.summary, "Napping")
        _ = watch.update([thread("a", .running)])
        XCTAssertEqual(watch.summary, "1 agent working")
        _ = watch.update([thread("a", .running), thread("b", .running)])
        XCTAssertEqual(watch.summary, "2 agents working")
        _ = watch.update([thread("a", .waitingForApproval)])
        XCTAssertEqual(watch.summary, "Something needs you")
    }
}

final class LayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testSitsAboveTheCatAndPointsAtIt() {
        let cat = CGRect(x: 1300, y: 20, width: 64, height: 64)
        let placement = BubbleLayout.place(size: CGSize(width: 340, height: 120), over: cat, in: screen)
        XCTAssertFalse(placement.below)
        XCTAssertEqual(placement.frame.minY, cat.maxY + BubbleLayout.gap)
        XCTAssertEqual(placement.frame.minX + placement.tailX, cat.midX, accuracy: 1)
        XCTAssertTrue(screen.contains(placement.frame))
    }

    func testGrowsTowardTheMiddleOfTheScreen() {
        let left = CGRect(x: 20, y: 20, width: 64, height: 64)
        let placement = BubbleLayout.place(size: CGSize(width: 340, height: 120), over: left, in: screen)
        XCTAssertGreaterThan(placement.frame.maxX, left.maxX)
    }

    func testHangsBelowWhenThereIsNoRoomAbove() {
        let cat = CGRect(x: 600, y: 820, width: 64, height: 64)
        let placement = BubbleLayout.place(size: CGSize(width: 340, height: 120), over: cat, in: screen)
        XCTAssertTrue(placement.below)
        XCTAssertLessThan(placement.frame.maxY, cat.minY)
        XCTAssertTrue(screen.contains(placement.frame))
    }

    func testAlwaysStaysOnScreen() {
        for x in stride(from: 0.0, through: 1376.0, by: 172) {
            for y in stride(from: 0.0, through: 836.0, by: 209) {
                let cat = CGRect(x: x, y: y, width: 64, height: 64)
                let placement = BubbleLayout.place(size: CGSize(width: 340, height: 300), over: cat, in: screen)
                XCTAssertTrue(screen.contains(placement.frame), "\(cat) -> \(placement.frame)")
            }
        }
    }

    func testAGiantBubbleStillStartsOnScreen() {
        let cat = CGRect(x: 600, y: 400, width: 64, height: 64)
        let placement = BubbleLayout.place(size: CGSize(width: 340, height: 880), over: cat, in: screen)
        XCTAssertGreaterThanOrEqual(placement.frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(placement.frame.maxY, screen.maxY)
    }

    func testClampsToTheNearestScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        let size = CGSize(width: 64, height: 64)
        XCTAssertEqual(ScreenBounds.clamp(CGPoint(x: 100, y: 100), size: size, to: screens), CGPoint(x: 100, y: 100))
        XCTAssertEqual(ScreenBounds.clamp(CGPoint(x: -50, y: 100), size: size, to: screens), CGPoint(x: 0, y: 100))
        XCTAssertEqual(ScreenBounds.clamp(CGPoint(x: 2500, y: 900), size: size, to: screens), CGPoint(x: 1936, y: 736))
    }

    func testRemembersASpotOnAScreenThatIsNowGone() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800)]
        XCTAssertEqual(ScreenBounds.clamp(CGPoint(x: 1500, y: 300), size: CGSize(width: 64, height: 64), to: screens), CGPoint(x: 936, y: 300))
    }
}

final class WordsTests: XCTestCase {
    private struct Friendly: LocalizedError {
        var errorDescription: String? { "T3 Code isn't running. Open it and try again." }
    }

    private struct Plain: Error {}

    func testFriendlyModelNames() {
        XCTAssertEqual(ModelNames.friendly(.frontier), "Opus")
        XCTAssertEqual(ModelNames.friendly(.quick), "GPT-6.1 Sol")
        XCTAssertEqual(ModelNames.friendly(model: "claude-sonnet-5-5"), "Sonnet")
        XCTAssertEqual(ModelNames.friendly(model: "claude-fable-5-1"), "Fable")
        XCTAssertEqual(ModelNames.friendly(model: "llama-3"), "llama-3")
    }

    func testAModulesOwnMessageWins() {
        XCTAssertEqual(CatWords.problem(Friendly(), while: .agents), "T3 Code isn't running. Open it and try again.")
    }

    func testEveryProblemHasAShortLine() {
        for doing in [CatWords.Doing.agents, .seeing, .listening, .typing, .keys] {
            let line = CatWords.problem(Plain(), while: doing)
            XCTAssertFalse(line.isEmpty)
            XCTAssertLessThan(line.count, 100)
        }
    }

    func testSettingsReadsModels() {
        let fallback = ModelChoice.quick
        XCTAssertEqual(SettingsPanel.model("a / b / c", fallback: fallback), ModelChoice(provider: "a", model: "b", effort: "c"))
        XCTAssertEqual(SettingsPanel.model("nonsense", fallback: fallback), fallback)
    }
}
