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

final class ScreenWordsTests: XCTestCase {
    func testWordsThatOnlyMakeSenseWithTheScreen() {
        for words in [
            "Read this x thread, and see what lessons we can take from it to improve our kitten litter.",
            "look at this",
            "See this? Do that for the kittens",
            "What's this?",
            "What\u{2019}s this?",
            "whats this",
            "what does this say",
            "What does this error mean?",
            "what are these",
            "Summarize this",
            "check out this repo",
            "thoughts on this?",
            "what do you think of this",
            "What can we learn from this article?",
            "Is this reddit post right about the install?",
            "compare these screenshots",
            "this\nvideo",
            "what's on my screen?",
            "what I'm looking at",
            "the article I\u{2019}m reading",
            "Quick one: read this x thread",
            "He said \"wow\" about this article",
        ] {
            XCTAssertTrue(ScreenWords.pointAtScreen(words), words)
        }
    }

    func testWordsThatStandOnTheirOwn() {
        for words in [
            "Steve should stop doing that",
            "and that part?",
            "Make the bubble a little bigger",
            "Fix the install script",
            "Stop doing this",
            "Let's do this",
            "Why did this happen?",
            "Can you ship this today?",
            "Does this fix the error?",
            "Check that the page loads",
            "I read that the new model is out",
            "the cat sits too low on the screen",
            "I'm reading the logs now",
        ] {
            XCTAssertFalse(ScreenWords.pointAtScreen(words), words)
        }
    }

    func testThisWeekPointsAtTheCalendar() {
        for words in [
            "What should we build this week?",
            "What's this month's budget?",
            "What's this week looking like?",
            "What does this month look like for rent?",
            "What does this Friday mean for the release?",
            "What's this Friday look like?",
            "Look at this month's spending and tell me if I'm over",
            "Summarize this week",
            "Summarize this past week",
            "Check out this coming week's schedule",
            "Thoughts on this week's plan?",
            "What do you think of this week's release?",
            "Read this week's notes and tell me what's due",
            "Check out this weekend's schedule",
            "Write this week's blog post",
            "Send this week's email to the team",
            "What do people read these days?",
        ] {
            XCTAssertFalse(ScreenWords.pointAtScreen(words), words)
        }
    }

    func testThisAloneIsntEnough() {
        for words in [
            "What does this change do?",
            "Explain this function",
            "What is this test for?",
            "Is this error fixed now?",
            "Is this doc up to date?",
            "Is this page up to date?",
            "What are these warnings in the build?",
            "Did this comment get pushed?",
            "What does this PR do?",
            "See this through to the end",
            "Is this thread-safe?",
            "Does this window take focus?",
            "Make this page load faster",
            "Export this to PDF",
        ] {
            XCTAssertFalse(ScreenWords.pointAtScreen(words), words)
        }
    }

    func testAFollowUpsThisIsUsuallyTheSessionsOwnWork() {
        for words in [
            "Look at this error",
            "Look at this function and fix it",
            "Read this file and tell me what it does",
            "Check out this branch and run the tests",
            "Summarize this PR",
            "Translate this function to Swift",
            "what does this say?",
            "What's this?",
        ] {
            XCTAssertFalse(ScreenWords.pointAtScreen(words, isFollowUp: true), words)
            XCTAssertTrue(ScreenWords.pointAtScreen(words), "a new thread has nothing else it could mean: \(words)")
        }
    }

    func testAFollowUpStillWarnsWhenItNamesSomethingOutsideTheConversation() {
        for words in [
            "Read this x thread, and see what lessons we can take from it to improve our kitten litter.",
            "Is this tweet right?",
            "what's on my screen?",
            "the article I'm reading",
        ] {
            XCTAssertTrue(ScreenWords.pointAtScreen(words, isFollowUp: true), words)
        }
    }

    func testALinkMeansTheyAlreadySentIt() {
        XCTAssertFalse(ScreenWords.pointAtScreen("Read this x thread https://x.com/someone/status/1"))
        XCTAssertFalse(ScreenWords.pointAtScreen("Read this x thread x.com/someone/status/1"))
        XCTAssertFalse(ScreenWords.pointAtScreen("Read this www.example.com"))
    }

    /// Doing what the cat says mustn't get the same advice again.
    func testPastedTextDoesntGetAskedForAgain() {
        for words in [
            "Summarize this: the build failed because the signing key expired.",
            "Read this: Shades is a desktop cat.",
            "Translate this to Spanish: where is the library?",
            "Thoughts on this tweet: \"ship small, ship often\"",
            "Read this \"ship small, ship often\"",
            "Read this \u{201C}ship small, ship often\u{201D}",
            "The build failed because the signing key expired. Summarize this.",
            "Build failed: errSecInternalComponent on codesign. What does this mean?",
            "ship small, ship often. Thoughts on this?",
            "\"ship small, ship often\" what do you think of this?",
            "\"ship small, ship often\"\n\nRead this and tell me what lessons we can take from it",
        ] {
            XCTAssertFalse(ScreenWords.pointAtScreen(words), words)
        }
    }

    func testPunctuationAloneIsntPastedText() {
        for words in [
            "Read this x thread, and see what lessons we can take from it to improve our kitten litter :)",
            "Read this x thread before my 3:30 call",
            "Read this:",
            "Read this :)",
            "Read this \"",
            "Hey there: read this x thread",
        ] {
            XCTAssertTrue(ScreenWords.pointAtScreen(words), words)
        }
    }

    func testLotsOfTextMeansTheyPastedIt() {
        let fits = "Read this " + String(repeating: "x", count: 270)
        XCTAssertEqual(fits.count, 280)
        XCTAssertTrue(ScreenWords.pointAtScreen(fits))
        XCTAssertFalse(ScreenWords.pointAtScreen(fits + "x"))
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
        XCTAssertEqual(ModelNames.friendly(ModelChoice(provider: "codex", model: "gpt-6.1-sol", effort: "medium")), "GPT-6.1 Sol")
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

@MainActor
final class InputPanelKeysTests: XCTestCase {
    func testReturnSendsAndShiftReturnDoesnt() {
        XCTAssertTrue(InputPanel.returnSends([]))
        XCTAssertTrue(InputPanel.returnSends(.command))
        XCTAssertFalse(InputPanel.returnSends(.shift))
        XCTAssertFalse(InputPanel.returnSends([.shift, .capsLock]))
    }
}

final class KittenBoardTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_000)
    private let steve = Kitten(name: "Steve", role: "Professional", covers: "", folder: "/k/steve")
    private let pepper = Kitten(name: "Pepper", role: "Finance", covers: "", folder: "/k/pepper", planned: true)

    private func thread(_ id: String, _ status: AgentStatus, title: String = "Work", project: String? = "Steve", age: TimeInterval = 0) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: project, status: status, model: "m", updatedAt: at.addingTimeInterval(-age))
    }

    private func status(_ threads: [AgentThread]) -> KittenStatus {
        KittenBoard.statuses(kittens: [steve], threads: threads)[0]
    }

    func testIdleWithNothingToOpen() {
        let idle = status([thread("x", .running, project: "Someone else")])
        XCTAssertEqual(idle.state, .idle)
        XCTAssertNil(idle.threadID)
    }

    func testIdleOpensTheLatestThing() {
        let idle = status([thread("old", .completed, age: 100), thread("new", .completed, age: 1)])
        XCTAssertEqual(idle.state, .idle)
        XCTAssertEqual(idle.threadID, "new")
    }

    func testCountsWhatItsWorkingOn() {
        let working = status([thread("a", .running, age: 5), thread("b", .starting, age: 1), thread("c", .completed)])
        XCTAssertEqual(working.state, .working(sessions: 2))
        XCTAssertEqual(working.threadID, "b")
    }

    func testAThreadInAnotherProjectCountsIfItCarriesTheName() {
        let working = status([thread("site", .running, title: "Steve: Shrink logos", project: "personal-website")])
        XCTAssertEqual(working.state, .working(sessions: 1))
    }

    func testWhatNeedsYouComesBeforeEverythingElse() {
        let asking = status([thread("a", .running, age: 0), thread("q", .waitingForAnswer, age: 50)])
        XCTAssertEqual(asking.state, .needsYou)
        XCTAssertEqual(asking.threadID, "q")
    }

    func testKittensThatArentSetUpGoLastAndDontMove() {
        let statuses = KittenBoard.statuses(kittens: [pepper, steve], threads: [])
        XCTAssertEqual(statuses.map(\.kitten.name), ["Steve", "Pepper"])
        XCTAssertEqual(statuses[1].state, .notSetUp)
        XCTAssertEqual(statuses[1].pose(tick: 0), statuses[1].pose(tick: 7))
    }

    func testAJacketTakesItsColour() {
        let pose = CatPose(frame: .sit)
        XCTAssertEqual(CatRenderer.pixels(for: pose, theme: .light), CatRenderer.pixels(for: pose, theme: .light, jacket: nil))
        XCTAssertNotEqual(CatRenderer.pixels(for: pose, theme: .light), CatRenderer.pixels(for: pose, theme: .light, jacket: 0xb3261e))
    }
}

final class HealthCheckTests: XCTestCase {
    func testAllGoodHasNoProblems() {
        XCTAssertTrue(HealthCheck.findings(from: HealthFacts()).allSatisfy(\.ok))
    }

    func testABadSignatureHidesThePermissionsItWouldMakeLookOff() {
        let facts = HealthFacts(isSignedWithIdentity: false, hasScreenRecording: false, hasAccessibility: false)
        let problems = HealthCheck.findings(from: facts).filter { !$0.ok }
        XCTAssertEqual(problems.map(\.check), [HealthCheck.signature])
    }

    func testARunWithoutABundleDoesntCareAboutItsSignature() {
        let facts = HealthFacts(isBundled: false, isSignedWithIdentity: false)
        XCTAssertTrue(HealthCheck.findings(from: facts).allSatisfy(\.ok))
    }

    func testAnInvalidSignatureCountsToo() {
        let facts = HealthFacts(signatureIsValid: false)
        XCTAssertEqual(HealthCheck.findings(from: facts).filter { !$0.ok }.map(\.check), [HealthCheck.signature])
    }

    func testEachMissingThingIsNamed() {
        let facts = HealthFacts(
            hasScreenRecording: false,
            hasAccessibility: false,
            hasInputMonitoring: false,
            microphoneDenied: true,
            skillsInstalled: false,
            reachedT3: false
        )
        let problems = HealthCheck.findings(from: facts).filter { !$0.ok }.map(\.check)
        XCTAssertEqual(problems, ["screen recording", "accessibility", "input monitoring", "microphone", "T3 Code", "kitten skills"])
    }

    func testAReportIsOnlyOkIfEverythingIs() {
        let good = [HealthFinding.good("a")]
        let bad = good + [HealthFinding(check: "b", ok: false, problem: "p", fix: "f")]
        XCTAssertTrue(HealthCheck.report(good, pid: 1, version: "v", at: Date()).ok)
        XCTAssertFalse(HealthCheck.report(bad, pid: 1, version: "v", at: Date()).ok)
    }
}
