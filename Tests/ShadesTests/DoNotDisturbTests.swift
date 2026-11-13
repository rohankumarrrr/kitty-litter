@testable import Shades
import ShadesCore
import XCTest

/// Do Not Disturb: every way something pops up by itself stays quiet while it's on, nothing it held is lost, and
/// turning it off brings one catch-up.
@MainActor
final class DoNotDisturbTests: XCTestCase {
    private var stage: FakeStage!
    private var backend: FakeBackend!
    private var clock = Date(timeIntervalSince1970: 100_000)
    private var kittens: [Kitten] = []
    private var savedSettings: Settings?
    private var savedInbox: Inbox?
    private var notified: [NeedsYouAlert] = []
    private var controller: AppController!
    private let clawde = Kitten(name: "Clawde", role: "The system", covers: "the app", folder: "/k/clawde", seesScreen: false, usesInbox: true)
    private let steve = Kitten(name: "Steve", role: "Careers", covers: "jobs", folder: "/k/steve")

    override func setUp() async throws {
        stage = FakeStage(log: Log())
        backend = FakeBackend()
        controller = makeController()
    }

    /// The app as it comes up: a new one of these, with what the last one saved, is a restart.
    private func makeController(settings: Settings = Settings(), inbox: Inbox = Inbox(since: .distantPast)) -> AppController {
        var settings = settings
        settings.quickMode = .approvalRequired
        let controller = AppController(
            dependencies: AppDependencies(
                backend: backend,
                context: FakeContext(log: Log()),
                voice: FakeVoice(),
                inserter: FakeInserter(),
                keys: FakeKeys(),
                settings: settings,
                saveSettings: { [unowned self] in self.savedSettings = $0 },
                kittens: { [unowned self] in self.kittens },
                routerFolder: { "/shades/router" },
                inbox: inbox,
                saveInbox: { [unowned self] in self.savedInbox = $0 },
                notify: { [unowned self] in self.notified.append($0) }
            ),
            stage: stage,
            now: { [unowned self] in self.clock }
        )
        controller.threadListWait = 0
        controller.reportDelay = 0
        return controller
    }

    private func quiet() {
        controller.doNotDisturbPressed()
        XCTAssertTrue(controller.settings.doNotDisturb)
    }

    private func work(_ id: String, title: String = "Work", status: AgentStatus = .completed, folder: String? = nil, run: String = "run-1") -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: nil, status: status, model: "m", updatedAt: clock, projectPath: folder, lastRunID: run, lastRunEndedAt: clock)
    }

    /// Runs, then finishes and says `report`.
    private func finish(_ thread: AgentThread, report: String, sorted: String? = nil) async {
        backend.reports[thread.id] = report
        if let sorted { backend.replies.append([.finished(fullText: sorted)]) }
        var running = thread
        running.status = .running
        controller.threadsChanged([running])
        controller.threadsChanged([thread])
        await settle()
    }

    private func settle() async {
        for _ in 0..<50 {
            await controller.reportTask?.value
            await controller.replyTask?.value
            await Task.yield()
        }
    }

    private func asking(_ id: String = "r1", thread: String = "w") -> AgentThread {
        let request = ApprovalRequest(id: id, threadID: thread, threadTitle: "Work", kind: .command, summary: "npm test", createdAt: clock)
        return AgentThread(id: thread, title: "Work", projectTitle: "site", status: .waitingForApproval, model: "m", updatedAt: clock, pendingApprovals: [request])
    }

    private func question(_ id: String = "q", thread: String = "w") -> AgentThread {
        var asking = work(thread, status: .waitingForAnswer)
        asking.pendingQuestion = AgentQuestion(id: id, threadID: thread, threadTitle: "Work", text: "Which month?", askedAt: clock)
        return asking
    }

    // MARK: - Nothing pops up

    func testAKittensReplyWaitsWithoutABubbleOrASummaryButWhatItNeedsFromYouIsKept() async {
        kittens = [steve]
        quiet()
        await finish(work("s", title: "Steve: Resume", folder: steve.folder), report: String(repeating: "Your resume is ready. ", count: 40), sorted: "DECISION: Send it?")
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertEqual(backend.sent.count, 1, "sorted for what needs you, and nothing summed up for a bubble that won't show")
        XCTAssertEqual(controller.inbox.entries.map(\.text), ["Send it?"])
        XCTAssertEqual(controller.away, [.thread("s")])
    }

    func testAnInboxReportIsFiledWithoutANudge() async {
        kittens = [clawde]
        quiet()
        await finish(work("c", title: "Clawde: Fix login", folder: clawde.folder), report: "Merged.", sorted: "DECISION: Ship it?")
        XCTAssertEqual(controller.inbox.entries.map(\.text), ["Ship it?"], "it's filed as usual")
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertEqual(controller.away, [.thread("c")])
    }

    func testAQuestionWaitsUnansweredWithoutABubbleOrNotification() async {
        quiet()
        controller.threadsChanged([question()])
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertEqual(controller.waiting.questions.map(\.id), ["q"], "still waiting in Messages")
        XCTAssertEqual(controller.away, [.question("q")])
    }

    func testAnApprovalWaitsWithoutTheCatComingOrAnyoneAnsweringIt() async {
        quiet()
        controller.threadsChanged([asking()])
        controller.threadsChanged([asking()])
        XCTAssertEqual(stage.came, 0)
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertTrue(backend.responses.isEmpty, "nothing denies it for being ignored")
        XCTAssertEqual(controller.approvals.pending.map(\.id), ["r1"])
        XCTAssertEqual(controller.away, [.approval("r1")])

        controller.catClicked()
        XCTAssertEqual(stage.bubble, .approval(controller.approvals.pending[0], position: 1, total: 1), "you're there, so clicking the cat shows it")
    }

    func testEveryApprovalIsKeptHoweverTheyCome() async {
        quiet()
        controller.threadsChanged([asking("r1", thread: "a")])
        controller.threadsChanged([asking("r1", thread: "a"), asking("r2", thread: "b")])
        XCTAssertEqual(controller.away, [.approval("r1"), .approval("r2")])
    }

    func testAFinishedNotificationWaitsAndIsntSentLate() async {
        kittens = [clawde, steve]
        var settings = controller.settings
        settings.notifyFinished = true
        controller.apply(settings)
        quiet()
        await finish(work("c", title: "Clawde: Fix login", folder: clawde.folder), report: "Merged.", sorted: "SHIPPED: The fix is live.")
        await finish(work("s", title: "Steve: Resume", folder: steve.folder), report: "Your resume is ready.")
        XCTAssertTrue(notified.isEmpty)
        XCTAssertEqual(controller.away, [.thread("c"), .thread("s")])

        controller.doNotDisturbPressed()
        controller.threadsChanged([work("c", title: "Clawde: Fix login", folder: clawde.folder), work("s", title: "Steve: Resume", folder: steve.folder)])
        XCTAssertTrue(notified.isEmpty, "the catch-up covers them")
        XCTAssertEqual(stage.bubble, .inbox("While you were away: 2 replies."))
    }

    func testTheCatsOwnLinesWaitToo() async {
        quiet()
        controller.shortcutTaken("⌃⌘B")
        controller.passedOn(work("a"), to: "b")
        XCTAssertNil(stage.bubble)
        XCTAssertEqual(controller.away, [.line(CatWords.shortcutTaken("⌃⌘B")), .thread("b")])
    }

    func testAHandOffThatFailsPartwayWaitsButOneThatCantStartSaysSo() async {
        quiet()
        backend.replies = [[.failed(message: "It ran into a problem.")]]
        controller.startFrontier(title: "Fix it", text: "Fix it", snapshot: nil)
        await controller.frontierTask?.value
        XCTAssertEqual(stage.bubble, .line(CatWords.onIt(modelName: controller.frontierName), threadID: "thread-1"), "what answers you still shows")
        XCTAssertEqual(controller.away, [.line("It ran into a problem.")])

        let error = URLError(.notConnectedToInternet)
        backend.streamError = error
        controller.startFrontier(title: "Fix it", text: "Fix it", snapshot: nil)
        await controller.frontierTask?.value
        XCTAssertEqual(stage.bubble, .line(CatWords.problem(error, while: .agents), threadID: nil))
    }

    func testWhatWasWaitingAtLaunchDoesntPopUp() async {
        kittens = [clawde]
        var inbox = Inbox(since: .distantPast)
        inbox.file(SortedReport(decision: "Ship it?"), from: work("c"), at: clock) { "row" }
        controller = makeController(settings: Settings(doNotDisturb: true), inbox: inbox)
        controller.start()
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(stage.doNotDisturb, "the cat's curled up")
    }

    func testTurningItOnPutsAwayALineThatCameByItselfButNotOneAnsweringYou() async {
        controller.shortcutTaken("⌃⌘B")
        quiet()
        XCTAssertNil(stage.bubble)
        XCTAssertEqual(controller.away, [.line(CatWords.shortcutTaken("⌃⌘B"))])

        controller.say("Sent.")
        controller.doNotDisturbPressed()
        quiet()
        XCTAssertEqual(stage.bubble, .line("Sent.", threadID: nil))
    }

    func testTurningItOnPutsAwayWhatsUpAndHidesApprovals() async {
        kittens = [steve]
        await finish(work("s", title: "Steve: Resume", folder: steve.folder), report: "Your resume is ready.")
        controller.threadsChanged([work("s", folder: steve.folder), asking()])
        XCTAssertNotNil(stage.bubble)
        quiet()
        XCTAssertNil(stage.bubble)
        XCTAssertTrue(controller.notices.isEmpty)
        XCTAssertEqual(controller.away, [.thread("s")], "the report that was up is kept")
        XCTAssertEqual(controller.approvals.pending.count, 1, "the approval keeps waiting")
    }

    func testWhatYouAskStillAnswers() async {
        quiet()
        backend.replies = [[.text(delta: "Hi."), .finished(fullText: "Hi.")]]
        controller.ask("hello", snapshot: nil)
        await settle()
        XCTAssertEqual(stage.bubble, .reply(text: "Hi.", done: true, threadID: "thread-1", note: nil))
        XCTAssertTrue(controller.away.isEmpty)
    }

    // MARK: - Catching up

    func testTurningItOffBringsOneCatchUpAndNothingLate() async {
        kittens = [steve]
        quiet()
        await finish(work("s", title: "Steve: Resume", folder: steve.folder), report: "Your resume is ready.")
        controller.threadsChanged([work("s", folder: steve.folder), asking()])
        controller.threadsChanged([work("s", folder: steve.folder), asking(), question(thread: "x")])
        let shown = stage.bubbles.count

        controller.doNotDisturbPressed()
        XCTAssertFalse(stage.doNotDisturb)
        XCTAssertEqual(stage.bubble, .inbox("While you were away: 1 reply, 1 approval, 1 question."))
        XCTAssertEqual(stage.bubbles.dropFirst(shown).compactMap { $0 }.count, 1, "one bubble, not a pile")
        controller.threadsChanged([work("s", folder: steve.folder), asking(), question(thread: "x")])
        XCTAssertTrue(notified.isEmpty, "what was held isn't sent late")
        XCTAssertEqual(stage.came, 0)
        XCTAssertEqual(stage.bubble, .inbox("While you were away: 1 reply, 1 approval, 1 question."))

        controller.bubbleDismissed(byClick: true)
        XCTAssertNotNil(stage.bubble, "a click elsewhere doesn't lose it")
        controller.bubbleAction(.openMessages)
        XCTAssertEqual(stage.selections.last ?? nil, .activity)
        XCTAssertNil(stage.bubble)
    }

    func testActivityShowsEverythingInTheOrderItCameWithItsUsualButtons() async {
        kittens = [clawde]
        quiet()
        controller.threadsChanged([asking("r1", thread: "a")])
        controller.threadsChanged([asking("r1", thread: "a"), question("q", thread: "b")])
        await finish(work("c", title: "Clawde: Fix login", folder: clawde.folder), report: "Merged.", sorted: "DECISION: Ship it?")
        controller.threadsChanged([asking("r1", thread: "a"), question("q", thread: "b"), work("c", title: "Clawde: Fix login", folder: clawde.folder)])
        controller.doNotDisturbPressed()
        controller.bubbleAction(.openMessages)

        let rows = ChannelRows.rows(.activity, in: stage.channelsShown.last!)
        guard rows.count > 4,
              case .section(CatWords.whileAwayTitle, nil) = rows[0],
              case .approval(let request) = rows[1],
              case .question(let asked) = rows[2],
              case .report(let report) = rows[3]
        else { return XCTFail("\(rows)") }
        XCTAssertEqual([request.id, asked.id, report.text], ["r1", "q", "Ship it?"])
        let again = rows.dropFirst(4).filter { row in
            switch row {
            case .approval, .question, .report: true
            default: false
            }
        }
        XCTAssertEqual(again, [], "each shows once")
    }

    func testOnceYouveSeenItClosingMessagesMeansYouCaughtUp() async {
        quiet()
        controller.threadsChanged([question()])
        controller.doNotDisturbPressed()
        controller.bubbleAction(.openMessages)
        controller.messagesAction(.seen(.activity))
        XCTAssertEqual(controller.away, [.question("q")], "still there while you're looking")
        controller.channelsClosed()
        XCTAssertTrue(controller.away.isEmpty)
        XCTAssertEqual(savedInbox?.away, [])
    }

    // MARK: - Across a restart

    func testItStaysOnAndKeepsOnlyIDsAcrossARestart() async throws {
        quiet()
        controller.shortcutTaken("⌃⌘B")
        controller.threadsChanged([question()])
        XCTAssertEqual(savedSettings?.doNotDisturb, true)
        let saved = try XCTUnwrap(savedInbox)
        XCTAssertEqual(saved.away, [.question("q")], "a line is words, so it isn't saved")

        controller = makeController(settings: try XCTUnwrap(savedSettings), inbox: saved)
        controller.start()
        XCTAssertTrue(controller.settings.doNotDisturb)
        XCTAssertTrue(stage.doNotDisturb)
        controller.threadsChanged([question()])
        XCTAssertNil(stage.bubble)
        controller.doNotDisturbPressed()
        XCTAssertEqual(stage.bubble, .inbox("While you were away: 1 question."))
    }

    func testASettingsPanelOpenedBeforeCantFlipItBack() async {
        controller.settingsPressed()
        quiet()
        var saved = Settings()
        saved.vocabulary = ["Shades"]
        controller.settingsEdited(saved)
        XCTAssertEqual(controller.settings.vocabulary, ["Shades"])
        XCTAssertTrue(controller.settings.doNotDisturb)
    }
}
